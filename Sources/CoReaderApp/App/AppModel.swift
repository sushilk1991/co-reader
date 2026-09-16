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
    private var pageSummaries: [String: String] = [:]
    private var pageSummaryFailures: [String: String] = [:]
    private var conceptsByPage: [String: [String]] = [:]
    private var summaryTask: Task<Void, Never>?
    private var lastAutoSummaryKey: String?
    private var highlightLoadTask: Task<Void, Never>?
    private var visualExtractionTask: Task<Void, Never>?
    private var currentVisualExtractionID: UUID?
    private var askTask: Task<Void, Never>?
    private var currentAskID: UUID?
    private var hasRestoredReadingState = false
    private var canPersistReadingState = true
    private let autoSummaryDelay: Duration
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
    var totalDocumentPages: Int?
    var chatInput = ""
    var chatError: String?
    var chatTranscript: [ChatMessage] = []
    var askProgress: DocumentAssistantProgress?
    var isExtractingVisuals = false
    var visualExtractionProgress: PageScanProgress?
    var visualExtractionError: String?
    var autoSummaryError: String?
    var isRestoringReadingState = false
    var readingStateRestoreError: String?
    var missingLibraryFiles: [URL] = []

    /// Auto-summaries wait for the reader to settle on a page before spending a
    /// model call on it.
    static let defaultAutoSummaryDelay: Duration = .seconds(4)
    private static let savedNotesLimit = 20

    init(
        providerDiscovery: AIProviderDiscovery = .live(),
        documentAssistant: DocumentAssisting = DocumentAssistant(),
        knowledgeCapture: KnowledgeCapturing? = nil,
        noteStore: KnowledgeNoteStoring? = nil,
        highlightStore: DocumentHighlightStoring? = nil,
        visualExtractor: DocumentVisualExtracting = LiveDocumentVisualExtractor(),
        visualExporter: DocumentVisualExporting = LiveDocumentVisualExporter(),
        readingStateStore: ReadingStateStore? = nil,
        autoSummaryDelay: Duration = AppModel.defaultAutoSummaryDelay
    ) {
        self.providerDiscovery = providerDiscovery
        self.documentAssistant = documentAssistant
        self.visualExtractor = visualExtractor
        self.visualExporter = visualExporter
        self.autoSummaryDelay = autoSummaryDelay
        let systems = AppModel.defaultKnowledgeSystems()
        self.knowledgeCapture = knowledgeCapture ?? systems.capture
        self.noteStore = noteStore ?? systems.noteStore
        self.highlightStore = highlightStore ?? AppModel.defaultHighlightStore()
        self.readingStateStore = readingStateStore ?? AppModel.defaultReadingStateStore()
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

    /// Why no page can be summarised right now. Read from provider state whenever
    /// the card is built, never stored, so it clears as soon as a provider appears.
    var autoSummaryUnavailableReason: String? {
        guard hasLoadedProviders, !isDiscoveringProviders,
              let blocker = providerStatuses.textAnswerBlocker else {
            return nil
        }

        return blocker.localizedDescription
    }

    /// The card over the current page: a summary, one page's recorded failure, or
    /// the live no-provider notice, in that order.
    var summaryCardContent: PageSummaryCardContent? {
        if let autoSummary {
            return .summary(autoSummary)
        }

        if let autoSummaryError {
            return .failure(autoSummaryError)
        }

        if let autoSummaryUnavailableReason {
            return .unavailable(autoSummaryUnavailableReason)
        }

        return nil
    }

    /// Why the readiness pill says what it says: one line per offline provider.
    var providerReadinessDetail: String {
        if isDiscoveringProviders {
            return "Checking Ollama and the Claude CLI."
        }

        let offline = providerStatuses.filter { !$0.isAvailable }
        guard !offline.isEmpty else {
            return statusDetail
        }

        return offline
            .map { "\($0.kind.displayName): \($0.detail)" }
            .joined(separator: "\n")
    }

    /// Something about the last session that the user needs to know: files that
    /// could not be found, or a state file that could not be read.
    var sessionNotice: String? {
        if let readingStateRestoreError {
            return readingStateRestoreError
        }

        guard !missingLibraryFiles.isEmpty else {
            return nil
        }

        let names = missingLibraryFiles.map(\.lastPathComponent).joined(separator: ", ")
        return "\(missingLibraryFiles.count) file(s) from your last session could not be found and were removed from the library: \(names)"
    }

    var currentPageLabel: String? {
        guard let currentPageIndex else {
            return nil
        }

        if let total = totalDocumentPages {
            return "\(locationLabel(for: currentPageIndex)) of \(total)"
        }

        return locationLabel(for: currentPageIndex)
    }

    var readingProgress: Double {
        guard let currentPageIndex, let total = totalDocumentPages, total > 0 else {
            return 0
        }
        return Double(currentPageIndex + 1) / Double(total)
    }

    func updateTotalPages(_ count: Int) {
        totalDocumentPages = count
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
            return "Checking Ollama and the Claude CLI."
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

    /// Loads the last session off the main actor (the file may live in iCloud and
    /// be a not-yet-downloaded placeholder), then merges it with whatever the user
    /// has already opened this launch.
    func restoreReadingStateIfNeeded() async {
        guard !hasRestoredReadingState, let readingStateStore else {
            return
        }

        hasRestoredReadingState = true
        isRestoringReadingState = true
        defer { isRestoringReadingState = false }

        do {
            let state = try await BlockingWork.run { _ in try readingStateStore.load() }
            restoreFromReadingState(state)
        } catch ReadingStateStoreError.notYetDownloaded {
            // Writing now would replace the newer state iCloud is still fetching.
            canPersistReadingState = false
            readingStateRestoreError = ReadingStateStoreError.notYetDownloaded.localizedDescription
        } catch {
            readingStateRestoreError = "Could not restore your last session: \(error.localizedDescription)"
        }
    }

    /// Skips the save debounce; used when the app is about to quit.
    func saveReadingStateNow() {
        readingStateSaveTask?.cancel()
        persistReadingState()
    }

    func dismissSessionNotice() {
        readingStateRestoreError = nil
        missingLibraryFiles = []
    }

    /// The page to reopen a document on, if one was recorded.
    func readingPosition(for document: ReaderDocument) -> Int? {
        readingPositionsByDocument[positionKey(for: document)]
    }

    /// Makes notes synced from another Mac searchable; the SQLite index is local-only.
    func rebuildKnowledgeIndexIfNeeded() async {
        guard let noteStore else {
            return
        }

        do {
            let changes = try await noteStore.rebuildIndexFromMarkdown()
            guard changes > 0 else {
                return
            }

            try refreshSavedNotesForSelectedDocument()
        } catch {
            chatError = "Note index rebuild failed: \(error.localizedDescription)"
        }
    }

    func cancelVisualExtraction() {
        visualExtractionTask?.cancel()
        isExtractingVisuals = false
        visualExtractionProgress = nil
    }

    func cancelQuestion() {
        askTask?.cancel()
    }

    func dismissAutoSummary() {
        autoSummary = nil
        autoSummaryError = nil
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

    func capturePDFHighlights(_ drafts: [PDFDocumentHighlightDraft]) async {
        guard let document = selectedDocument else {
            return
        }

        // A pending activation read must not replace the result of this edit.
        highlightLoadTask?.cancel()

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

                try await highlightStore.upsertHighlight(highlight, for: document)

                let note = KnowledgeNote(
                    id: draft.id,
                    kind: .highlight,
                    title: "\(document.title) Highlight",
                    sourceIdentifier: document.noteSourceIdentifier,
                    createdAt: highlight.createdAt,
                    bulletPoints: [
                        "Saved from page \(draft.pageIndex + 1).",
                        draft.quotedText
                    ],
                    highlightExcerpt: draft.quotedText,
                    pageIndex: draft.pageIndex,
                    notePreview: nil
                )
                try noteStore?.save(note: note)
            }

            // Keep completion for an old document from changing the current reader.
            guard selectedDocument?.id == document.id else {
                return
            }

            try refreshSavedNotesForSelectedDocument()
            try await refreshDocumentHighlights()
            guard selectedDocument?.id == document.id else {
                return
            }

            openInspector(tab: .highlights)
        } catch {
            guard selectedDocument?.id == document.id else {
                return
            }

            chatError = error.localizedDescription
        }
    }

    func deleteHighlight(_ highlightID: UUID) async {
        guard let document = selectedDocument else {
            return
        }

        // A pending activation read must not replace the result of this edit.
        highlightLoadTask?.cancel()

        do {
            try await highlightStore.removeHighlight(id: highlightID, for: document)
            try noteStore?.delete(noteID: highlightID)
            // Keep completion for an old document from changing the current reader.
            guard selectedDocument?.id == document.id else {
                return
            }

            try refreshSavedNotesForSelectedDocument()
            try await refreshDocumentHighlights()
        } catch {
            guard selectedDocument?.id == document.id else {
                return
            }

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
            sourceIdentifier: document.noteSourceIdentifier,
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
        // The library lists newest first and `importDocument` inserts at the front,
        // so replay the saved order back to front to keep it stable across launches.
        for url in state.documentURLs.reversed() {
            guard FileManager.default.fileExists(atPath: url.path) else {
                missingLibraryFiles.append(url)
                continue
            }
            _ = documentLibrary.importDocument(at: url)
        }

        // Positions recorded this launch are newer than the file's.
        readingPositionsByDocument.merge(state.positions) { current, _ in current }

        if selectedDocument == nil,
           let activeURL = state.activeDocumentURL,
           let doc = documentLibrary.documents.first(where: { $0.fileURL == activeURL.standardizedFileURL }) {
            activateDocument(doc)
        }
    }

    private func positionKey(for document: ReaderDocument) -> String {
        document.fileURL.standardizedFileURL.path
    }

    private func persistReadingState() {
        guard let readingStateStore, canPersistReadingState else { return }

        // Saving before the restore lands would overwrite the file with a partial library.
        guard !isRestoringReadingState else {
            scheduleReadingStateSave()
            return
        }

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

        let isNewPage = key != lastAutoSummaryKey
        if isNewPage {
            lastAutoSummaryKey = key
            autoSummaryError = nil
        }

        if let cached = pageSummaries[key] {
            // A dismissed card stays hidden until the reader returns from another page.
            guard isNewPage else {
                return
            }

            autoSummary = cached
            autoConceptTags = conceptsByPage[key] ?? []
            return
        }

        if let failure = pageSummaryFailures[key] {
            if isNewPage {
                autoSummaryError = failure
            }
            return
        }

        summaryTask?.cancel()
        summaryTask = Task {
            try? await Task.sleep(for: autoSummaryDelay)
            guard !Task.isCancelled else { return }
            guard self.selectedDocument?.id == document.id,
                  self.currentPageIndex == pageIndex else { return }
            guard providerStatuses.textAnswerBlocker == nil else { return }

            do {
                let answer = try await documentAssistant.answer(
                    question: "Provide a concise 2-3 sentence summary of this section's key points. Then on a new line starting with 'Tags:', list 3-5 key concepts as comma-separated tags.",
                    for: document,
                    providerStatuses: providerStatuses,
                    scope: .focus,
                    selection: nil,
                    currentPageIndex: pageIndex,
                    visiblePageIndexes: [pageIndex],
                    visualAsset: nil,
                    onProgress: { _ in }
                )

                let cleanedAnswer = Self.stripThinkingTags(answer)
                let (summary, tags) = parseSummaryAndTags(cleanedAnswer)
                pageSummaries[key] = summary
                conceptsByPage[key] = tags

                if self.selectedDocument?.id == document.id,
                   self.currentPageIndex == pageIndex {
                    autoSummary = summary
                    autoConceptTags = tags
                }
            } catch where Self.isCancellation(error) {
                return
            } catch {
                // One attempt per page: a failing provider must not be hit on every scroll.
                let failure = "Auto-summary failed: \(error.localizedDescription)"
                pageSummaryFailures[key] = failure
                guard self.selectedDocument?.id == document.id,
                      self.currentPageIndex == pageIndex else { return }
                autoSummaryError = failure
            }
        }
    }

    private static func stripThinkingTags(_ text: String) -> String {
        text.replacingOccurrences(
            of: "<think>[\\s\\S]*?</think>",
            with: "",
            options: .regularExpression
        ).trimmingCharacters(in: .whitespacesAndNewlines)
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
            .map { $0.replacingOccurrences(of: "\\*+", with: "", options: .regularExpression) }
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
        autoSummaryError = nil
        lastAutoSummaryKey = nil
        autoConceptTags = []
        totalDocumentPages = nil
        summaryTask?.cancel()
        askTask?.cancel()
        currentAskID = nil
        isAskingQuestion = false
        askProgress = nil

        currentPageIndex = readingPositionsByDocument[positionKey(for: document)]

        try? refreshSavedNotesForSelectedDocument()
        // Loading can await iCloud; obsolete document loads must not publish into the new selection.
        highlightLoadTask?.cancel()
        highlightLoadTask = Task { [weak self] in
            do {
                try await self?.refreshDocumentHighlights()
            } catch is CancellationError {
                return
            } catch {
                guard let self, self.selectedDocument?.id == document.id, !Task.isCancelled else {
                    return
                }

                self.chatError = error.localizedDescription
            }
        }
        startVisualExtraction(for: document)
    }

    /// Scans every page for figures on a GCD thread; the panel shows progress and
    /// a Cancel button meanwhile. Switching documents cancels the previous scan.
    private func startVisualExtraction(for document: ReaderDocument) {
        visualExtractionTask?.cancel()
        let extractionID = UUID()
        currentVisualExtractionID = extractionID
        isExtractingVisuals = true
        visualExtractionProgress = nil
        visualExtractionError = nil
        let extractor = visualExtractor
        // Progress arrives on the GCD thread; hop back to the actor to publish it.
        let reportProgress: @Sendable (PageScanProgress) -> Void = { [weak self] progress in
            Task { @MainActor in
                self?.noteVisualExtractionProgress(progress, extractionID: extractionID)
            }
        }

        visualExtractionTask = Task { [weak self] in
            defer { self?.finishVisualExtraction(extractionID: extractionID) }

            do {
                let visuals = try await BlockingWork.run { isCancelled in
                    try extractor.extractVisuals(for: document, isCancelled: isCancelled, onProgress: reportProgress)
                }

                guard let self, !Task.isCancelled, self.currentVisualExtractionID == extractionID else {
                    return
                }
                documentVisuals = visuals
                selectedVisual = visuals.first
            } catch is CancellationError {
                return
            } catch {
                guard let self, self.currentVisualExtractionID == extractionID else {
                    return
                }
                visualExtractionError = error.localizedDescription
            }
        }
    }

    private func noteVisualExtractionProgress(_ progress: PageScanProgress, extractionID: UUID) {
        guard currentVisualExtractionID == extractionID else {
            return
        }

        visualExtractionProgress = progress
    }

    private func finishVisualExtraction(extractionID: UUID) {
        guard currentVisualExtractionID == extractionID else {
            return
        }

        isExtractingVisuals = false
        visualExtractionProgress = nil
    }

    private func refreshSavedNotesForSelectedDocument() throws {
        guard let selectedDocument, let noteStore else {
            try refreshSavedNotes()
            return
        }

        savedNotes = try noteStore.notes(forSource: selectedDocument.noteSourceIdentifier, limit: Self.savedNotesLimit)
    }

    private func refreshDocumentHighlights() async throws {
        guard let selectedDocument else {
            savedHighlights = []
            pdfDocumentHighlights = []
            return
        }

        let storedHighlights = try await highlightStore.loadHighlights(for: selectedDocument)
        // A document switch or cancellation invalidates a load that finished later.
        guard self.selectedDocument?.id == selectedDocument.id, !Task.isCancelled else {
            return
        }

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
            sourceIdentifier: document.noteSourceIdentifier,
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
        if let selectedDocument, selectedDocument.noteSourceIdentifier == summary.sourceIdentifier {
            return selectedDocument.title
        }

        return URL(fileURLWithPath: summary.sourceIdentifier)
            .deletingPathExtension()
            .lastPathComponent
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

    /// Wraps the question in its own task so `cancelQuestion()` can stop text
    /// extraction between pages or abandon a slow model.
    private func submitQuestion(_ question: String, for document: ReaderDocument, scope: DocumentQueryScope, visualAsset: DocumentVisualAsset?) async {
        askTask?.cancel()
        let askID = UUID()
        currentAskID = askID
        let task = Task {
            await performQuestion(question, for: document, scope: scope, visualAsset: visualAsset, askID: askID)
        }
        askTask = task
        await task.value
    }

    /// A superseded ask (another question submitted while this one was in flight)
    /// must not touch the shared in-progress state the newer ask now owns.
    private func performQuestion(_ question: String, for document: ReaderDocument, scope: DocumentQueryScope, visualAsset: DocumentVisualAsset?, askID: UUID) async {
        chatError = nil
        chatInput = ""
        isAskingQuestion = true
        askProgress = nil
        chatTranscript.append(ChatMessage(role: .user, content: question))
        defer {
            if currentAskID == askID {
                isAskingQuestion = false
                askProgress = nil
            }
        }

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
                visualAsset: visualAsset,
                onProgress: { [weak self] progress in
                    Task { @MainActor in
                        guard let self, self.currentAskID == askID else {
                            return
                        }

                        self.askProgress = progress
                    }
                }
            )
            guard currentAskID == askID else {
                return
            }

            chatTranscript.append(ChatMessage(role: .assistant, content: Self.stripThinkingTags(answer)))

            do {
                try knowledgeCapture.capture(question: question, answer: answer, for: document)
                capturedNoteCount += 1
            } catch {
                chatError = "Answer generated, but note capture failed: \(error.localizedDescription)"
            }
        } catch where Self.isCancellation(error) {
            guard currentAskID == askID else {
                return
            }

            chatTranscript.append(ChatMessage(role: .assistant, content: Self.cancelledAnswerText))
        } catch {
            chatError = error.localizedDescription
            chatTranscript.append(ChatMessage(role: .assistant, content: error.localizedDescription))
        }
    }

    private static let cancelledAnswerText = "Cancelled before an answer arrived."

    /// Cancellation arrives in three shapes: `CancellationError` from `BlockingWork`
    /// and `ProcessCommandRunner`, `URLError(.cancelled)` from `URLSession`, and a
    /// provider error thrown after the task itself was cancelled.
    private static func isCancellation(_ error: Error) -> Bool {
        error is CancellationError || (error as? URLError)?.code == .cancelled || Task.isCancelled
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
