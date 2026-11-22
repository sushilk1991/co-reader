import AppKit
import CoreaderKit
import SwiftUI

struct ChatMessage: Identifiable, Equatable {
    enum Role { case user, assistant }
    let id = UUID()
    var role: Role
    var text: String
    /// Passage the question is about, shown as a quote above the user's words.
    var quote: String?
    var attachment: URL?
    /// What the agent is doing right now ("Reading chapter 3…"), while streaming.
    var activity: String?
    var isStreaming = false
    var failed = false
    var saved = false
}

/// What the agent is told to look at for a question.
enum ChatScope: String, CaseIterable, Identifiable {
    case page, book, notes
    var id: String { rawValue }
    var title: String {
        switch self {
        case .page: "This page"
        case .book: "Whole book"
        case .notes: "My notes"
        }
    }
}

/// One conversation with an agent CLI about the open book. The agent keeps its own
/// session, so follow-up questions continue the same thread until "New chat".
@MainActor
@Observable
final class ChatModel {
    @ObservationIgnored weak var reader: ReaderModel?

    var messages: [ChatMessage] = []
    var draft = ""
    var pendingQuote: ReaderSelection?
    var pendingAttachment: URL?
    var scope: ChatScope = .page
    var isResponding = false
    var composerFocusToken = 0

    @ObservationIgnored private var session: AgentSession?
    @ObservationIgnored private var sessionAgent: AgentKind?
    @ObservationIgnored private var turn: Task<Void, Never>?

    var app: AppModel? { reader?.app }

    func focusComposer() { composerFocusToken += 1 }

    func quote(_ selection: ReaderSelection) {
        pendingQuote = selection
        focusComposer()
    }

    func attach(image: URL) {
        pendingAttachment = image
        focusComposer()
    }

    func newChat() {
        stop()
        messages = []
        session = nil
        pendingQuote = nil
        pendingAttachment = nil
    }

    func stop() {
        turn?.cancel()
        session?.cancel()
        isResponding = false
        if let last = messages.indices.last, messages[last].isStreaming {
            messages[last].isStreaming = false
            messages[last].activity = nil
            if messages[last].text.isEmpty { messages.removeLast() }
        }
    }

    // MARK: Sending

    func send(_ text: String? = nil, display: String? = nil) {
        let typed = (text ?? draft).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !isResponding, let reader, let app else { return }
        guard !typed.isEmpty || pendingQuote != nil || pendingAttachment != nil else { return }
        guard let agent = app.activeAgent else {
            messages.append(ChatMessage(role: .assistant, text: "No AI agent was found on this Mac. Install Claude Code, Codex or Antigravity (and sign in once in a terminal), then choose **Check again** in Settings.", failed: true))
            return
        }
        let quote = pendingQuote
        let attachment = pendingAttachment
        if text == nil { draft = "" }
        pendingQuote = nil
        pendingAttachment = nil

        let question = typed.isEmpty ? (quote != nil ? "Explain this passage." : "What does this image show?") : typed
        messages.append(ChatMessage(role: .user, text: display ?? question, quote: quote?.text, attachment: attachment))
        messages.append(ChatMessage(role: .assistant, text: "", activity: "Thinking…", isStreaming: true))
        let replyID = messages[messages.count - 1].id
        isResponding = true

        let prompt = buildPrompt(question: question, quote: quote, reader: reader)
        if session == nil || sessionAgent != agent.kind {
            session = AgentSession(agent: agent, config: sessionConfig(reader: reader, app: app))
            sessionAgent = agent.kind
        }
        guard let session else { return }

        turn = Task { [weak self] in
            do {
                for try await event in session.send(prompt, attachments: attachment.map { [$0] } ?? []) {
                    guard let self, let i = self.messages.firstIndex(where: { $0.id == replyID }) else { return }
                    switch event {
                    case .sessionStarted:
                        break
                    case .textDelta(let delta):
                        self.messages[i].text += delta
                        self.messages[i].activity = nil
                    case .activity(let status):
                        self.messages[i].activity = status
                    case .completed(let full):
                        if !full.isEmpty { self.messages[i].text = full }
                    }
                }
                self?.finish(replyID, error: nil)
            } catch {
                self?.finish(replyID, error: error)
            }
        }
    }

    private func finish(_ id: UUID, error: Error?) {
        isResponding = false
        guard let i = messages.firstIndex(where: { $0.id == id }) else { return }
        messages[i].isStreaming = false
        messages[i].activity = nil
        if let error, !(error is CancellationError) {
            if case AgentError.cancelled = error { return }
            let reason = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            if messages[i].text.isEmpty { messages[i].text = reason } else { messages[i].text += "\n\n_\(reason)_" }
            messages[i].failed = true
            // A broken native session cannot be continued; the next question starts fresh.
            session = nil
        } else if messages[i].text.isEmpty {
            messages[i].text = "The agent finished without an answer. Try asking again."
            messages[i].failed = true
        }
    }

    // MARK: Prompts

    private func sessionConfig(reader: ReaderModel, app: AppModel) -> AgentSessionConfig {
        let book = reader.book
        let textFolder = app.textStore.folder(for: book.id)
        let isPDF = book.format == .pdf
        let linkRule = isPDF
            ? "cite pages as Markdown links like [p. 12](coreader://open?book=\(book.id)&page=12)"
            : "each text file starts with a `coreader://` link for its section; cite sections as Markdown links using that exact link, e.g. [Chapter 3](coreader://open?book=\(book.id)&cfi=…)"
        let system = """
        You are the reading companion inside Coreader, a reading app. The person is reading \
        "\(book.title)"\(book.authorLine.isEmpty ? "" : " by \(book.authorLine)").

        Where things are:
        - The full text of the book, split into numbered Markdown files (one per \(isPDF ? "page" : "section")): \(textFolder.path)
        - Their own highlights and notes for this book: \(reader.entry.notesURL.path)
        - Their whole reading library (one folder per book, each with notes.md): \(app.library.root.path)

        How to answer:
        - Ground answers in the book. Read the relevant files before answering questions about the book; do not answer from memory when the text is available.
        - When you point to a place in the book, \(linkRule). The app turns these into buttons that jump to the passage, so include them whenever you tell the reader where to look or what to read next.
        - Be concise and concrete. Use short paragraphs; use lists only for steps or parallel items. No preamble and no closing offers.
        - Use Markdown. Put code in fenced blocks. Write maths as plain text or LaTeX in `$...$`.
        - When teaching, go step by step: check what they already know, explain one idea at a time with a small example or exercise, and say which pages to read next.
        - Do not modify files unless asked to.
        """
        return AgentSessionConfig(workingDirectory: reader.entry.folder,
                                  additionalDirectories: [textFolder, app.library.root],
                                  systemPrompt: system, access: .readOnly, model: nil)
    }

    private func buildPrompt(question: String, quote: ReaderSelection?, reader: ReaderModel) -> String {
        var parts: [String] = []
        let place = [reader.chapter, reader.pageLabel].filter { !$0.isEmpty }.joined(separator: ", ")
        if !place.isEmpty { parts.append("[I am at: \(place), \(Int(reader.fraction * 100))% through the book]") }
        if let quote {
            parts.append("Selected passage\(quote.locator.label.map { " (\($0))" } ?? ""):\n\"\"\"\n\(quote.text)\n\"\"\"")
            if quote.context.count > quote.text.count + 40 { parts.append("Paragraph around it:\n\"\"\"\n\(quote.context)\n\"\"\"") }
        } else {
            switch scope {
            case .page:
                if !reader.visibleText.isEmpty { parts.append("Text on the page in front of me:\n\"\"\"\n\(reader.visibleText)\n\"\"\"") }
            case .book:
                parts.append("[This question is about the whole book: read the text files as needed.]")
            case .notes:
                parts.append("[This question is about my highlights and notes: read notes.md (and other books' notes.md in the library if useful).]")
            }
        }
        parts.append(question)
        return parts.joined(separator: "\n\n")
    }

    // MARK: Keeping answers

    func saveToNotes(_ id: UUID) {
        guard let reader, let i = messages.firstIndex(where: { $0.id == id }) else { return }
        let question = i > 0 && messages[i - 1].role == .user ? messages[i - 1] : nil
        var note = messages[i].text
        if let q = question, !q.text.isEmpty { note = "**Q: \(q.text)**\n\n" + note }
        reader.addNote(note, quote: question?.quote?.collapsingWhitespace ?? "")
        messages[i].saved = true
    }

    func copy(_ id: UUID) {
        guard let m = messages.first(where: { $0.id == id }) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(m.text, forType: .string)
    }

    // MARK: Presets

    struct Preset: Identifiable {
        let id = UUID()
        var title: String
        var symbol: String
        var scope: ChatScope
        var prompt: String
    }

    var presets: [Preset] {
        let isPaper = reader?.book.kind == .paper
        var list = [
            Preset(title: "Summarize this page", symbol: "text.alignleft", scope: .page,
                   prompt: "Summarize what is on this page in a few sentences, then give the one idea worth remembering."),
            Preset(title: "Recap so far", symbol: "arrow.counterclockwise", scope: .book,
                   prompt: "Give me a 'previously on' recap of the book up to where I am now, without anything from later. Six sentences at most, then the three threads to keep in mind going forward."),
            Preset(title: "Teach me this book", symbol: "graduationcap", scope: .book,
                   prompt: "Act as my tutor for this book. First skim its structure, then propose a study plan of short sessions: for each, the goal, the exact pages or sections to read (as links), and one exercise I should be able to do afterwards. Then ask me what I already know so you can adjust, and begin session one when I answer. Teach from the basics, one idea at a time, and check my understanding before moving on."),
            Preset(title: "Quiz me", symbol: "questionmark.bubble", scope: .book,
                   prompt: "Quiz me on what I have read so far (up to my current position). Ask one question at a time, wait for my answer, tell me whether it is right and which page settles it, then ask the next. Start with recall and move to questions that need understanding."),
        ]
        if isPaper {
            list.insert(Preset(title: "Explain this paper", symbol: "doc.text.magnifyingglass", scope: .book,
                               prompt: "Explain this paper: the problem, the key idea, how the method works, the main results, and its limitations. Link the pages for each part. Then list the three earlier papers I would need to understand it and why."), at: 1)
        }
        return list
    }

    func run(_ preset: Preset) {
        scope = preset.scope
        send(preset.prompt, display: preset.title)
    }
}
