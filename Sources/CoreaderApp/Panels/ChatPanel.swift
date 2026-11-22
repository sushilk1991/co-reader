import AppKit
import CoreaderKit
import SwiftUI

/// The AI side panel: a continuing conversation with the agent CLI found on this Mac.
struct ChatPanel: View {
    let reader: ReaderModel
    @Bindable var chat: ChatModel
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var palette
    @FocusState private var composerFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            if chat.messages.isEmpty {
                starter
            } else {
                transcript
            }
            composer
        }
        .background(palette.surface)
        .environment(\.openURL, OpenURLAction { url in
            if url.scheme == DeepLink.scheme { app.handle(url: url) } else { NSWorkspace.shared.open(url) }
            return .handled
        })
        .onChange(of: chat.composerFocusToken) { composerFocused = true }
        .onAppear { composerFocused = true }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 8) {
            Menu {
                if app.agents.isEmpty {
                    Text(app.agentsChecked ? "No agent found on this Mac" : "Looking for agents…")
                } else {
                    Picker("Agent", selection: Binding(get: { app.activeAgent?.kind }, set: { kind in
                        if kind != app.preferredAgent { chat.newChat() }
                        app.preferredAgent = kind
                    })) {
                        ForEach(app.agents) { agent in
                            Text(agent.kind.displayName).tag(Optional(agent.kind))
                        }
                    }
                    .pickerStyle(.inline)
                }
            } label: {
                HStack(spacing: 5) {
                    Circle().fill(app.activeAgent == nil ? palette.tertiary : Color(hex: 0x4E9A5A)).frame(width: 6, height: 6)
                    Text(app.activeAgent?.kind.displayName ?? (app.agentsChecked ? "No agent" : "Detecting…"))
                        .font(Typo.display(15))
                        .foregroundStyle(palette.ink)
                    Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold)).foregroundStyle(palette.tertiary)
                }
            }
            .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
            .help("Choose which agent answers")

            Spacer()

            if !chat.messages.isEmpty {
                Button { chat.newChat() } label: {
                    Image(systemName: "square.and.pencil").font(.system(size: 13)).foregroundStyle(palette.secondary)
                        .frame(width: 26, height: 26).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("New chat")
                .accessibilityLabel("New chat")
            }
            Button { reader.panel = nil } label: {
                Image(systemName: "xmark").font(.system(size: 11, weight: .medium)).foregroundStyle(palette.tertiary)
                    .frame(width: 24, height: 24).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close chat")
        }
        .padding(.horizontal, 20)
        .frame(height: 50)
        .overlay(alignment: .bottom) { Rectangle().fill(palette.rule.opacity(0.7)).frame(height: 0.5) }
    }

    // MARK: Empty state

    private var starter: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Ask about\n\(reader.book.title)")
                    .font(Typo.display(22, weight: .regular))
                    .foregroundStyle(palette.ink)
                    .lineSpacing(2)
                    .padding(.top, 28)
                Text(app.activeAgent == nil
                     ? (app.agentsChecked ? "Coreader uses the agent apps on your Mac. Install Claude Code, Codex or Antigravity to chat with your books." : "Looking for Claude Code, Codex and Antigravity…")
                     : "Select any passage and choose Ask, or start with one of these. The conversation continues until you start a new one.")
                    .font(Typo.ui(12.5))
                    .foregroundStyle(palette.secondary)
                    .lineSpacing(3)
                    .padding(.top, 8)

                VStack(spacing: 6) {
                    ForEach(chat.presets) { preset in
                        Button { chat.run(preset) } label: {
                            HStack(spacing: 10) {
                                Image(systemName: preset.symbol)
                                    .font(.system(size: 13))
                                    .foregroundStyle(palette.accent)
                                    .frame(width: 20)
                                Text(preset.title).font(Typo.ui(13)).foregroundStyle(palette.ink)
                                Spacer()
                            }
                            .padding(.horizontal, 12)
                            .frame(height: 38)
                            .background(palette.raised, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(palette.rule, lineWidth: 0.5))
                        }
                        .buttonStyle(.plain)
                        .disabled(app.activeAgent == nil)
                    }
                }
                .padding(.top, 22)
            }
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: Transcript

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    ForEach(chat.messages) { message in
                        MessageView(chat: chat, message: message).id(message.id)
                    }
                    Color.clear.frame(height: 1).id("end")
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 18)
            }
            .onChange(of: chat.messages.last?.text) { proxy.scrollTo("end", anchor: .bottom) }
            .onChange(of: chat.messages.count) { withAnimation { proxy.scrollTo("end", anchor: .bottom) } }
        }
    }

    // MARK: Composer

    private var composer: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let quote = chat.pendingQuote {
                HStack(alignment: .top, spacing: 8) {
                    Text(quote.text)
                        .font(Typo.serif(12.5, italic: true))
                        .foregroundStyle(palette.secondary)
                        .lineLimit(3)
                        .padding(.leading, 10)
                        .overlay(alignment: .leading) { Rectangle().fill(palette.accent).frame(width: 2) }
                    Spacer(minLength: 0)
                    Button { chat.pendingQuote = nil } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(palette.tertiary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Remove quoted passage")
                }
            }
            if let image = chat.pendingAttachment, let ns = NSImage(contentsOf: image) {
                HStack(alignment: .top, spacing: 8) {
                    Image(nsImage: ns).resizable().aspectRatio(contentMode: .fit).frame(maxHeight: 64)
                        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                    Spacer(minLength: 0)
                    Button { chat.pendingAttachment = nil } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(palette.tertiary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Remove image")
                }
            }

            TextField(chat.pendingQuote == nil ? "Ask anything about this book" : "Ask about the passage, or just press Return", text: $chat.draft, axis: .vertical)
                .textFieldStyle(.plain)
                .font(Typo.ui(13.5))
                .foregroundStyle(palette.ink)
                .lineLimit(1...8)
                .focused($composerFocused)
                .onSubmit { chat.send() }
                .onKeyPress(.return, phases: .down) { press in
                    // Shift-Return adds a line; Return sends.
                    if press.modifiers.contains(.shift) { chat.draft += "\n"; return .handled }
                    return .ignored
                }

            HStack(spacing: 6) {
                if chat.pendingQuote == nil {
                    Menu {
                        Picker("Look at", selection: $chat.scope) {
                            ForEach(ChatScope.allCases) { Text($0.title).tag($0) }
                        }
                        .pickerStyle(.inline)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: chat.scope == .page ? "doc.text" : (chat.scope == .book ? "book.closed" : "note.text")).font(.system(size: 10.5))
                            Text(chat.scope.title).font(Typo.ui(11.5))
                            Image(systemName: "chevron.down").font(.system(size: 7, weight: .bold))
                        }
                        .foregroundStyle(palette.secondary)
                        .padding(.horizontal, 8).frame(height: 24)
                        .background(palette.ink.opacity(0.05), in: Capsule())
                    }
                    .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
                    .help("What the agent should look at for this question")
                } else {
                    Text("About the selected passage").font(Typo.ui(11.5)).foregroundStyle(palette.tertiary)
                }
                Spacer()
                if chat.isResponding {
                    Button { chat.stop() } label: {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(palette.page)
                            .frame(width: 26, height: 26)
                            .background(palette.ink, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .help("Stop")
                    .accessibilityLabel("Stop answering")
                } else {
                    let canSend = !chat.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || chat.pendingQuote != nil || chat.pendingAttachment != nil
                    Button { chat.send() } label: {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(palette.page)
                            .frame(width: 26, height: 26)
                            .background(canSend ? palette.accent : palette.tertiary.opacity(0.5), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .disabled(!canSend)
                    .help("Send (Return)")
                    .accessibilityLabel("Send")
                }
            }
        }
        .padding(12)
        .background(palette.raised, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .strokeBorder(composerFocused ? palette.accent.opacity(0.45) : palette.rule, lineWidth: composerFocused ? 1 : 0.5))
        .padding(.horizontal, 14)
        .padding(.bottom, 14)
        .padding(.top, 6)
    }
}

private struct MessageView: View {
    let chat: ChatModel
    let message: ChatMessage
    @Environment(\.palette) private var palette
    @State private var hovering = false

    var body: some View {
        switch message.role {
        case .user:
            VStack(alignment: .trailing, spacing: 6) {
                if let quote = message.quote {
                    Text(quote)
                        .font(Typo.serif(12.5, italic: true))
                        .foregroundStyle(palette.secondary)
                        .lineLimit(4)
                        .padding(.leading, 10)
                        .overlay(alignment: .leading) { Rectangle().fill(palette.rule).frame(width: 2) }
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                if let url = message.attachment, let image = NSImage(contentsOf: url) {
                    Image(nsImage: image).resizable().aspectRatio(contentMode: .fit).frame(maxHeight: 120)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                Text(message.text)
                    .font(Typo.ui(13.5))
                    .foregroundStyle(palette.ink)
                    .textSelection(.enabled)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(palette.ink.opacity(0.07), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.leading, 36)

        case .assistant:
            VStack(alignment: .leading, spacing: 8) {
                if !message.text.isEmpty {
                    MarkdownText(text: message.text)
                        .textSelection(.enabled)
                        .opacity(message.failed ? 0.75 : 1)
                }
                if message.isStreaming {
                    HStack(spacing: 7) {
                        PulsingDot()
                        Text(message.activity ?? (message.text.isEmpty ? "Thinking…" : "Writing…"))
                            .font(Typo.ui(11.5))
                            .foregroundStyle(palette.tertiary)
                            .lineLimit(1)
                    }
                } else if !message.failed {
                    HStack(spacing: 12) {
                        Button { chat.saveToNotes(message.id) } label: {
                            Label(message.saved ? "Saved" : "Save to notes", systemImage: message.saved ? "checkmark" : "note.text.badge.plus")
                        }
                        .disabled(message.saved)
                        Button { chat.copy(message.id) } label: { Label("Copy", systemImage: "doc.on.doc") }
                    }
                    .buttonStyle(.plain)
                    .labelStyle(.titleAndIcon)
                    .font(Typo.ui(11.5))
                    .foregroundStyle(palette.tertiary)
                    .opacity(hovering || message.saved ? 1 : 0)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
        }
    }
}

private struct PulsingDot: View {
    @Environment(\.palette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var on = false

    var body: some View {
        Circle()
            .fill(palette.accent)
            .frame(width: 6, height: 6)
            .opacity(on ? 1 : 0.3)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) { on = true }
            }
    }
}
