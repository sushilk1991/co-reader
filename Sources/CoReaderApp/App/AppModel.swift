import Foundation
import Observation

@MainActor
@Observable
final class AppModel {
    let appTitle = "Co-Reader"
    private let providerDiscovery: AIProviderDiscovery
    private let documentAssistant: DocumentAssisting
    private let knowledgeCapture: KnowledgeCapturing
    private let noteStore: KnowledgeNoteStoring?
    private var documentLibrary = DocumentLibrary()
    private(set) var hasLoadedProviders = false
    var isDiscoveringProviders = false
    var isImportingDocument = false
    var isAskingQuestion = false
    var isLibraryVisible = false
    var isInspectorVisible = false
    var capturedNoteCount = 0
    var providerStatuses: [AIProviderStatus] = []
    var selectedDocument: ReaderDocument?
    var selectedInspectorTab: InspectorTab = .ask
    var currentSelection: DocumentSelection?
    var currentPageIndex: Int?
    var visiblePageIndexes: [Int] = []
    var noteDraft = ""
    var savedHighlights: [ReaderHighlight] = []
    var savedNotes: [KnowledgeNoteSummary] = []
    var chatInput = ""
    var chatError: String?
    var chatTranscript: [ChatMessage] = []

    init(
        providerDiscovery: AIProviderDiscovery = .live(),
        documentAssistant: DocumentAssisting = DocumentAssistant(),
        knowledgeCapture: KnowledgeCapturing? = nil,
        noteStore: KnowledgeNoteStoring? = nil
    ) {
        self.providerDiscovery = providerDiscovery
        self.documentAssistant = documentAssistant
        let systems = AppModel.defaultKnowledgeSystems()
        self.knowledgeCapture = knowledgeCapture ?? systems.capture
        self.noteStore = noteStore ?? systems.noteStore
    }

    var importedDocuments: [ReaderDocument] {
        documentLibrary.documents
    }

    var canSubmitQuestion: Bool {
        !chatInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            selectedDocument != nil &&
            !isAskingQuestion
    }

    var hasActiveSelection: Bool {
        currentSelection != nil
    }

    var providerReadinessLabel: String {
        if providerStatuses.contains(where: \.isAvailable) {
            return "Local AI Ready"
        }

        if isDiscoveringProviders {
            return "Scanning AI"
        }

        return "AI Offline"
    }

    var currentPageLabel: String? {
        guard let currentPageIndex else {
            return nil
        }

        return "Page \(currentPageIndex + 1)"
    }

    var selectionSummary: String? {
        guard let currentSelection else {
            return nil
        }

        let trimmed = currentSelection.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        return String(trimmed.prefix(140))
    }

    var statusHeadline: String {
        if isDiscoveringProviders {
            return "Scanning local AI providers."
        }

        if providerStatuses.contains(where: \.isAvailable) {
            return "Local AI integrations are ready."
        }

        if hasLoadedProviders {
            return "No local AI providers were detected."
        }

        return "Local AI integrations are initializing."
    }

    var statusDetail: String {
        if isDiscoveringProviders {
            return "Checking Ollama on localhost:11434 and looking for the claude CLI."
        }

        if hasLoadedProviders {
            return "Use Ollama or Claude locally to ask document questions, explain figures, and generate code snippets."
        }

        return "The first provider scan starts automatically when the window opens."
    }

    func refreshProvidersIfNeeded() async {
        guard !hasLoadedProviders, !isDiscoveringProviders else {
            return
        }

        await refreshProviders()
    }

    func beginDocumentImport() {
        isImportingDocument = true
    }

    func importDocument(from url: URL) {
        let document = documentLibrary.importDocument(at: url)
        activateDocument(document)
    }

    func selectDocument(_ document: ReaderDocument) {
        activateDocument(document)
    }

    func toggleLibrary() {
        isLibraryVisible.toggle()
    }

    func toggleInspector(preferredTab: InspectorTab? = nil) {
        isInspectorVisible.toggle()
        if let preferredTab {
            selectedInspectorTab = preferredTab
        }
    }

    func openInspector(tab: InspectorTab) {
        selectedInspectorTab = tab
        isInspectorVisible = true
    }

    func updateCurrentSelection(_ selection: DocumentSelection?) {
        currentSelection = selection
    }

    func updateReadingPosition(currentPageIndex: Int?, visiblePageIndexes: [Int] = []) {
        self.currentPageIndex = currentPageIndex
        self.visiblePageIndexes = visiblePageIndexes
    }

    func saveHighlightFromSelection() throws {
        guard let document = selectedDocument else {
            throw DocumentAssistantError.noSelectedDocument
        }

        guard let currentSelection else {
            throw ReaderWorkspaceError.noActiveSelection
        }

        let noteText = noteDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let savedHighlight = ReaderHighlight(
            id: UUID(),
            documentTitle: document.title,
            pageIndex: currentSelection.pageIndex,
            quotedText: currentSelection.text,
            noteText: noteText.isEmpty ? nil : noteText,
            createdAt: Date()
        )
        savedHighlights.insert(savedHighlight, at: 0)

        let note = KnowledgeNote(
            id: savedHighlight.id,
            title: "\(document.title) Highlight",
            sourceIdentifier: document.fileURL.lastPathComponent,
            createdAt: savedHighlight.createdAt,
            bulletPoints: highlightBulletPoints(noteText: noteText, selection: currentSelection),
            highlightExcerpt: currentSelection.text
        )
        try noteStore?.save(note: note)
        noteDraft = ""
        openInspector(tab: .highlights)
        try refreshSavedNotesForSelectedDocument()
    }

    func saveQuickHighlight() throws {
        let existingDraft = noteDraft
        noteDraft = ""

        do {
            try saveHighlightFromSelection()
        } catch {
            noteDraft = existingDraft
            throw error
        }
    }

    func saveNote() throws {
        guard let document = selectedDocument else {
            throw DocumentAssistantError.noSelectedDocument
        }

        let trimmedNote = noteDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedNote.isEmpty else {
            throw ReaderWorkspaceError.emptyNote
        }

        let note = KnowledgeNote(
            id: UUID(),
            title: "\(document.title) Note",
            sourceIdentifier: document.fileURL.lastPathComponent,
            createdAt: Date(),
            bulletPoints: noteBulletPoints(from: trimmedNote),
            highlightExcerpt: currentSelection?.text
        )

        try noteStore?.save(note: note)
        noteDraft = ""
        openInspector(tab: .notes)
        try refreshSavedNotesForSelectedDocument()
    }

    func refreshSavedNotes(query: String = "") throws {
        savedNotes = try noteStore?.searchNotes(matching: query, limit: 20) ?? []
    }

    func prepareSelectionNote() {
        if let currentSelection, noteDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            noteDraft = """
            Key idea:
            Why it matters:
            Follow-up:

            Quote: \(currentSelection.text)
            """
        }

        openInspector(tab: .notes)
    }

    func showHighlights() {
        openInspector(tab: .highlights)
    }

    func focusChat() {
        openInspector(tab: .ask)
    }

    func askAboutSelection() async {
        guard let selection = currentSelection else {
            openInspector(tab: .ask)
            return
        }

        chatInput = """
        Explain this selected passage from page \(selection.pageIndex + 1):

        "\(selection.text)"
        """
        openInspector(tab: .ask)
        await askQuestion()
    }

    func askQuestion() async {
        let question = chatInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty else {
            return
        }

        guard let document = selectedDocument else {
            chatError = DocumentAssistantError.noSelectedDocument.localizedDescription
            return
        }

        chatError = nil
        chatInput = ""
        isAskingQuestion = true
        chatTranscript.append(ChatMessage(role: .user, content: question))
        defer { isAskingQuestion = false }

        do {
            let answer = try await documentAssistant.answer(
                question: question,
                for: document,
                providerStatuses: providerStatuses,
                selection: currentSelection,
                currentPageIndex: currentPageIndex,
                visiblePageIndexes: visiblePageIndexes
            )
            chatTranscript.append(ChatMessage(role: .assistant, content: answer))

            do {
                try knowledgeCapture.capture(question: question, answer: answer, for: document)
                capturedNoteCount += 1
            } catch {
                chatError = "Answer generated, but note capture failed: \(error.localizedDescription)"
            }
        } catch {
            chatError = error.localizedDescription
            chatTranscript.append(ChatMessage(role: .assistant, content: error.localizedDescription))
        }
    }

    func runQuickAction(_ action: LearningAction) async {
        guard let document = selectedDocument else {
            chatError = DocumentAssistantError.noSelectedDocument.localizedDescription
            return
        }

        chatInput = action.prompt(for: document)
        await askQuestion()
    }

    func refreshProviders() async {
        isDiscoveringProviders = true
        defer { isDiscoveringProviders = false }

        do {
            providerStatuses = try await providerDiscovery.discoverProviders()
        } catch {
            providerStatuses = AIProviderKind.allCases.map {
                AIProviderStatus(
                    kind: $0,
                    isAvailable: false,
                    detail: error.localizedDescription,
                    models: []
                )
            }
        }

        hasLoadedProviders = true
    }

    private func highlightBulletPoints(noteText: String, selection: DocumentSelection) -> [String] {
        if !noteText.isEmpty {
            return [noteText]
        }

        return [
            "Saved from page \(selection.pageIndex + 1).",
            selection.surroundingText
        ]
    }

    private func noteBulletPoints(from noteText: String) -> [String] {
        let lines = noteText
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if !lines.isEmpty {
            return lines
        }

        return [noteText]
    }

    private static func defaultKnowledgeSystems() -> (capture: KnowledgeCapturing, noteStore: KnowledgeNoteStoring?) {
        guard let repository = try? KnowledgeRepository.liveDefault() else {
            return (NoOpKnowledgeCapture(), nil)
        }

        return (ChatKnowledgeCapture(repository: repository), repository)
    }

    private func activateDocument(_ document: ReaderDocument) {
        selectedDocument = document
        isLibraryVisible = false
        currentSelection = nil
        currentPageIndex = nil
        visiblePageIndexes = []
        noteDraft = ""
        chatInput = ""
        chatError = nil
        chatTranscript = []
        savedHighlights = []

        try? refreshSavedNotesForSelectedDocument()
    }

    private func refreshSavedNotesForSelectedDocument() throws {
        try refreshSavedNotes(query: selectedDocument?.fileURL.lastPathComponent ?? "")
    }
}

enum ReaderWorkspaceError: LocalizedError {
    case noActiveSelection
    case emptyNote

    var errorDescription: String? {
        switch self {
        case .noActiveSelection:
            "Select text in the document first."
        case .emptyNote:
            "Write a note before saving it."
        }
    }
}
