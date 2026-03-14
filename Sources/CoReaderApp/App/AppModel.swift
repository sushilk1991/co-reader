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
    private let highlightStore: DocumentHighlightStoring
    private let visualExtractor: DocumentVisualExtracting
    private let visualExporter: DocumentVisualExporting
    private let readingStateStore: ReadingStateStore?
    private var documentLibrary = DocumentLibrary()
    private var readingPositionsByDocument: [String: Int] = [:]
    private var readingStateSaveTask: Task<Void, Never>?
    private var summarizedPageKeys: Set<String> = []
    private var pageSummaries: [String: String] = [:]
    private var conceptsByPage: [String: [String]] = [:]
    private var summaryTask: Task<Void, Never>?
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
    var queryScope: DocumentQueryScope = .focus
    var isHighlightToolEnabled = false
    var selectedHighlightColor: ReaderHighlightColor = .yellow
    var currentSelection: DocumentSelection?
    var currentPageIndex: Int?
    var visiblePageIndexes: [Int] = []
    var documentVisuals: [DocumentVisualAsset] = []
    var selectedVisual: DocumentVisualAsset?
    var pdfDocumentHighlights: [PDFDocumentHighlight] = []
    var noteDraft = ""
    var savedHighlights: [ReaderHighlight] = []
    var savedNotes: [KnowledgeNoteSummary] = []
    var isCommandPaletteVisible = false
    var autoSummary: String?
    var autoConceptTags: [String] = []
    var chatInput = ""
    var chatError: String?
    var chatTranscript: [ChatMessage] = []

    init(
        providerDiscovery: AIProviderDiscovery = .live(),
        documentAssistant: DocumentAssisting = DocumentAssistant(),
        knowledgeCapture: KnowledgeCapturing? = nil,
        noteStore: KnowledgeNoteStoring? = nil,
        highlightStore: DocumentHighlightStoring? = nil,
        visualExtractor: DocumentVisualExtracting = LiveDocumentVisualExtractor(),
        visualExporter: DocumentVisualExporting = LiveDocumentVisualExporter(),
        readingStateStore: ReadingStateStore? = nil
    ) {
        self.providerDiscovery = providerDiscovery
        self.documentAssistant = documentAssistant
        self.visualExtractor = visualExtractor
        self.visualExporter = visualExporter
        let systems = AppModel.defaultKnowledgeSystems()
        self.knowledgeCapture = knowledgeCapture ?? systems.capture
        self.noteStore = noteStore ?? systems.noteStore
        self.highlightStore = highlightStore ?? AppModel.defaultHighlightStore()
        self.readingStateStore = readingStateStore ?? AppModel.defaultReadingStateStore()

        if let state = try? self.readingStateStore?.load() {
            restoreFromReadingState(state)
        }
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

    var allConceptTags: [String] {
        guard let selectedDocument else { return [] }
        let prefix = "\(selectedDocument.id)-"
        let docConcepts = conceptsByPage
            .filter { $0.key.hasPrefix(prefix) }
            .values
            .flatMap { $0 }
        return Array(Set(docConcepts)).sorted()
    }

    var supportsPersistentPDFHighlights: Bool {
        selectedDocument?.kind == .pdf
    }

    var effectiveQueryScope: DocumentQueryScope {
        if queryScope == .selection, currentSelection == nil {
            return .focus
        }

        return queryScope
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

        return locationLabel(for: currentPageIndex)
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
            return "Checking Ollama, LM Studio, and the Claude CLI."
        }

        if hasLoadedProviders {
            return "Use Ollama, LM Studio, or Claude locally to ask document questions, explain figures, and generate code snippets."
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
        scheduleReadingStateSave()
    }

    func selectDocument(_ document: ReaderDocument) {
        activateDocument(document)
    }

    func toggleLibrary() {
        isLibraryVisible.toggle()
    }

    func toggleHighlightTool() {
        guard supportsPersistentPDFHighlights else {
            return
        }

        isHighlightToolEnabled.toggle()
        if isHighlightToolEnabled {
            openInspector(tab: .highlights)
        }
    }

    func setHighlightColor(_ color: ReaderHighlightColor) {
        selectedHighlightColor = color
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
        if selection == nil, queryScope == .selection {
            queryScope = .focus
        }
    }

    func updateReadingPosition(currentPageIndex: Int?, visiblePageIndexes: [Int] = []) {
        self.currentPageIndex = currentPageIndex
        self.visiblePageIndexes = visiblePageIndexes

        if let selectedDocument, let currentPageIndex {
            readingPositionsByDocument[positionKey(for: selectedDocument)] = currentPageIndex
            scheduleReadingStateSave()
            triggerAutoSummary(document: selectedDocument, pageIndex: currentPageIndex)
        }
    }

    func setQueryScope(_ scope: DocumentQueryScope) {
        if scope == .selection, currentSelection == nil {
            queryScope = .focus
            return
        }

        queryScope = scope
    }

    func selectVisual(_ visual: DocumentVisualAsset) {
        selectedVisual = visual
        openInspector(tab: .visuals)
    }

    func capturePDFHighlights(_ drafts: [PDFDocumentHighlightDraft]) {
        guard let document = selectedDocument else {
            return
        }

        do {
            for draft in drafts {
                let highlight = PDFDocumentHighlight(
                    id: draft.id,
                    pageIndex: draft.pageIndex,
                    quotedText: draft.quotedText,
                    noteText: nil,
                    createdAt: Date(),
                    color: draft.color,
                    rects: draft.rects.map(PDFDocumentHighlight.HighlightRect.init(rect:))
                )

                try highlightStore.upsertHighlight(highlight, for: document)

                let note = KnowledgeNote(
                    id: draft.id,
                    kind: .highlight,
                    title: "\(document.title) Highlight",
                    sourceIdentifier: document.fileURL.lastPathComponent,
                    createdAt: highlight.createdAt,
                    bulletPoints: [
                        "Saved from \(locationLabel(for: draft.pageIndex).lowercased()).",
                        draft.quotedText
                    ],
                    highlightExcerpt: draft.quotedText,
                    pageIndex: draft.pageIndex,
                    notePreview: nil
                )
                try noteStore?.save(note: note)
            }

            try refreshSavedNotesForSelectedDocument()
            try refreshSavedHighlightsForSelectedDocument()
            openInspector(tab: .highlights)
        } catch {
            chatError = error.localizedDescription
        }
    }

    func deleteHighlight(_ highlightID: UUID) {
        guard let document = selectedDocument else {
            return
        }

        do {
            try highlightStore.removeHighlight(id: highlightID, for: document)
            try noteStore?.delete(noteID: highlightID)
            try refreshSavedNotesForSelectedDocument()
            try refreshSavedHighlightsForSelectedDocument()
        } catch {
            chatError = error.localizedDescription
        }
    }

    func exportSelectedVisual() throws -> URL {
        guard let document = selectedDocument else {
            throw DocumentAssistantError.noSelectedDocument
        }

        guard let visual = activeVisualForActions() else {
            throw ReaderWorkspaceError.noVisualContext
        }

        return try visualExporter.exportPNG(visual, for: document)
    }

    func saveHighlightFromSelection() throws {
        let noteText = noteDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        try saveHighlight(noteText: noteText.isEmpty ? nil : noteText)
        noteDraft = ""
    }

    func saveQuickHighlight() throws {
        try saveHighlight(noteText: nil)
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
            kind: .note,
            title: "\(document.title) Note",
            sourceIdentifier: document.fileURL.lastPathComponent,
            createdAt: Date(),
            bulletPoints: noteBulletPoints(from: trimmedNote),
            highlightExcerpt: currentSelection?.text,
            pageIndex: currentSelection?.pageIndex,
            notePreview: trimmedNote
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

    func locationLabel(for index: Int) -> String {
        switch selectedDocument?.kind {
        case .epub:
            "Chapter \(index + 1)"
        default:
            "Page \(index + 1)"
        }
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
        Explain this selected passage from \(locationLabel(for: selection.pageIndex).lowercased()):

        "\(selection.text)"
        """
        queryScope = .selection
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

        await submitQuestion(question, for: document, scope: effectiveQueryScope, visualAsset: nil)
    }

    func runQuickAction(_ action: LearningAction) async {
        guard let document = selectedDocument else {
            chatError = DocumentAssistantError.noSelectedDocument.localizedDescription
            return
        }

        switch action {
        case .explainVisuals:
            do {
                let visual = try resolveVisualForExplanation(in: document)
                openInspector(tab: .ask)
                await submitQuestion(action.prompt(for: document, scope: effectiveQueryScope), for: document, scope: effectiveQueryScope, visualAsset: visual)
            } catch {
                chatError = error.localizedDescription
                chatTranscript.append(ChatMessage(role: .assistant, content: error.localizedDescription))
            }
        default:
            chatInput = action.prompt(for: document, scope: effectiveQueryScope)
            await askQuestion()
        }
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
            "Saved from \(locationLabel(for: selection.pageIndex).lowercased()).",
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

    private static func defaultHighlightStore() -> DocumentHighlightStoring {
        (try? LiveDocumentHighlightStore.liveDefault()) ?? NoOpDocumentHighlightStore()
    }

    private static func defaultReadingStateStore() -> ReadingStateStore? {
        try? ReadingStateStore.live()
    }

    private func restoreFromReadingState(_ state: ReadingState) {
        for url in state.documentURLs {
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            _ = documentLibrary.importDocument(at: url)
        }

        readingPositionsByDocument = state.positions

        if let activeURL = state.activeDocumentURL,
           let doc = documentLibrary.documents.first(where: { $0.fileURL == activeURL.standardizedFileURL }) {
            activateDocument(doc)
        }
    }

    private func positionKey(for document: ReaderDocument) -> String {
        document.fileURL.standardizedFileURL.path
    }

    private func persistReadingState() {
        guard let readingStateStore else { return }

        if let selectedDocument, let currentPageIndex {
            readingPositionsByDocument[positionKey(for: selectedDocument)] = currentPageIndex
        }

        let state = ReadingState(
            documentURLs: documentLibrary.documents.map(\.fileURL),
            activeDocumentURL: selectedDocument?.fileURL,
            positions: readingPositionsByDocument
        )
        try? readingStateStore.save(state)
    }

    private func scheduleReadingStateSave() {
        readingStateSaveTask?.cancel()
        readingStateSaveTask = Task {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            persistReadingState()
        }
    }

    private func triggerAutoSummary(document: ReaderDocument, pageIndex: Int) {
        let key = "\(document.id)-\(pageIndex)"

        if let cached = pageSummaries[key] {
            autoSummary = cached
            autoConceptTags = conceptsByPage[key] ?? []
            return
        }

        guard !summarizedPageKeys.contains(key) else { return }

        summaryTask?.cancel()
        summaryTask = Task {
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            guard self.selectedDocument?.id == document.id,
                  self.currentPageIndex == pageIndex else { return }
            guard providerStatuses.contains(where: \.isAvailable) else { return }

            do {
                let answer = try await documentAssistant.answer(
                    question: "Provide a concise 2-3 sentence summary of this section's key points. Then on a new line starting with 'Tags:', list 3-5 key concepts as comma-separated tags.",
                    for: document,
                    providerStatuses: providerStatuses,
                    scope: .focus,
                    selection: nil,
                    currentPageIndex: pageIndex,
                    visiblePageIndexes: [pageIndex],
                    visualAsset: nil
                )

                let (summary, tags) = parseSummaryAndTags(answer)
                summarizedPageKeys.insert(key)
                pageSummaries[key] = summary
                conceptsByPage[key] = tags

                if self.selectedDocument?.id == document.id,
                   self.currentPageIndex == pageIndex {
                    autoSummary = summary
                    autoConceptTags = tags
                }
            } catch {
                // Silent failure for background feature
            }
        }
    }

    private func parseSummaryAndTags(_ text: String) -> (summary: String, tags: [String]) {
        let parts = text.components(separatedBy: "Tags:")
        let summary = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)

        guard parts.count > 1 else {
            return (summary, [])
        }

        let tags = parts[1]
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        return (summary, tags)
    }

    private func activateDocument(_ document: ReaderDocument) {
        if let previousDoc = selectedDocument, let pos = currentPageIndex {
            readingPositionsByDocument[positionKey(for: previousDoc)] = pos
        }

        selectedDocument = document
        isLibraryVisible = false
        currentSelection = nil
        visiblePageIndexes = []
        documentVisuals = []
        selectedVisual = nil
        pdfDocumentHighlights = []
        noteDraft = ""
        chatInput = ""
        chatError = nil
        chatTranscript = []
        queryScope = .focus
        isHighlightToolEnabled = false
        savedHighlights = []
        autoSummary = nil
        autoConceptTags = []
        summaryTask?.cancel()

        currentPageIndex = readingPositionsByDocument[positionKey(for: document)]

        try? refreshSavedNotesForSelectedDocument()
        try? refreshSavedHighlightsForSelectedDocument()
        documentVisuals = (try? visualExtractor.extractVisuals(for: document)) ?? []
        selectedVisual = documentVisuals.first
    }

    private func refreshSavedNotesForSelectedDocument() throws {
        try refreshSavedNotes(query: selectedDocument?.fileURL.lastPathComponent ?? "")
    }

    private func refreshSavedHighlightsForSelectedDocument() throws {
        guard let selectedDocument else {
            savedHighlights = []
            pdfDocumentHighlights = []
            return
        }

        let storedHighlights = try highlightStore.loadHighlights(for: selectedDocument)
        pdfDocumentHighlights = storedHighlights

        let notePreviewByID = Dictionary(uniqueKeysWithValues: savedNotes.map { ($0.id, $0.notePreview) })
        if storedHighlights.isEmpty {
            savedHighlights = savedNotes.compactMap(makeHighlight(from:))
        } else {
            savedHighlights = storedHighlights.map { highlight in
                ReaderHighlight(
                    id: highlight.id,
                    documentTitle: selectedDocument.title,
                    pageIndex: highlight.pageIndex,
                    quotedText: highlight.quotedText,
                    noteText: notePreviewByID[highlight.id] ?? highlight.noteText,
                    createdAt: highlight.createdAt,
                    color: highlight.color
                )
            }
        }
    }

    private func makeHighlight(from summary: KnowledgeNoteSummary) -> ReaderHighlight? {
        guard summary.kind == .highlight,
              let quotedText = summary.highlightExcerpt,
              let pageIndex = summary.pageIndex else {
            return nil
        }

        return ReaderHighlight(
            id: summary.id,
            documentTitle: documentTitle(for: summary),
            pageIndex: pageIndex,
            quotedText: quotedText,
            noteText: summary.notePreview,
            createdAt: summary.createdAt
        )
    }

    private func saveHighlight(noteText: String?) throws {
        guard let document = selectedDocument else {
            throw DocumentAssistantError.noSelectedDocument
        }

        guard let currentSelection else {
            throw ReaderWorkspaceError.noActiveSelection
        }

        let savedHighlight = ReaderHighlight(
            id: UUID(),
            documentTitle: document.title,
            pageIndex: currentSelection.pageIndex,
            quotedText: currentSelection.text,
            noteText: noteText,
            createdAt: Date()
        )
        savedHighlights.insert(savedHighlight, at: 0)

        let note = KnowledgeNote(
            id: savedHighlight.id,
            kind: .highlight,
            title: "\(document.title) Highlight",
            sourceIdentifier: document.fileURL.lastPathComponent,
            createdAt: savedHighlight.createdAt,
            bulletPoints: highlightBulletPoints(noteText: noteText ?? "", selection: currentSelection),
            highlightExcerpt: currentSelection.text,
            pageIndex: currentSelection.pageIndex,
            notePreview: noteText
        )
        try noteStore?.save(note: note)
        try refreshSavedNotesForSelectedDocument()
        openInspector(tab: .highlights)
    }

    private func documentTitle(for summary: KnowledgeNoteSummary) -> String {
        if let selectedDocument,
           selectedDocument.fileURL.lastPathComponent == summary.sourceIdentifier {
            return selectedDocument.title
        }

        return summary.sourceIdentifier
            .replacingOccurrences(of: ".pdf", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: ".epub", with: "", options: .caseInsensitive)
    }

    private func resolveVisualForExplanation(in document: ReaderDocument) throws -> DocumentVisualAsset {
        if let visual = activeVisualForActions() {
            return visual
        }

        if let currentPageIndex,
           let snapshot = try visualExtractor.renderPageSnapshot(for: document, pageIndex: currentPageIndex) {
            selectedVisual = snapshot
            return snapshot
        }

        throw ReaderWorkspaceError.noVisualContext
    }

    private func activeVisualForActions() -> DocumentVisualAsset? {
        if let selectedVisual {
            return selectedVisual
        }

        if let fallbackVisual = documentVisuals.first {
            selectedVisual = fallbackVisual
            return fallbackVisual
        }

        return nil
    }

    private func questionWithConversationContext(_ question: String) -> String {
        let recent = chatTranscript.suffix(4)
        guard !recent.isEmpty else { return question }

        var lines: [String] = ["Previous conversation:"]
        for msg in recent {
            let role = msg.role == .user ? "User" : "Assistant"
            lines.append("\(role): \(String(msg.content.prefix(250)))")
        }
        lines.append("")
        lines.append("Follow-up question:")
        lines.append(question)
        return lines.joined(separator: "\n")
    }

    private func submitQuestion(_ question: String, for document: ReaderDocument, scope: DocumentQueryScope, visualAsset: DocumentVisualAsset?) async {
        chatError = nil
        chatInput = ""
        isAskingQuestion = true
        chatTranscript.append(ChatMessage(role: .user, content: question))
        defer { isAskingQuestion = false }

        let enrichedQuestion = chatTranscript.count > 1 ? questionWithConversationContext(question) : question

        do {
            let answer = try await documentAssistant.answer(
                question: enrichedQuestion,
                for: document,
                providerStatuses: providerStatuses,
                scope: scope,
                selection: currentSelection,
                currentPageIndex: currentPageIndex,
                visiblePageIndexes: visiblePageIndexes,
                visualAsset: visualAsset
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
}

enum ReaderWorkspaceError: LocalizedError {
    case noActiveSelection
    case emptyNote
    case noVisualContext

    var errorDescription: String? {
        switch self {
        case .noActiveSelection:
            "Select text in the document first."
        case .emptyNote:
            "Write a note before saving it."
        case .noVisualContext:
            "No visual is selected, and the current page could not be turned into a diagram snapshot."
        }
    }
}
