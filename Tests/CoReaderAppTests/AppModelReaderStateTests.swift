import Foundation
import Testing
@testable import CoReaderApp

@MainActor
struct AppModelReaderStateTests {
    @Test
    func readerStartsInReaderFirstMode() {
        let appModel = AppModel(
            documentAssistant: StubDocumentAssistant(result: "Unused"),
            knowledgeCapture: StubKnowledgeCapture(),
            noteStore: StubNoteStore()
        )

        #expect(appModel.isLibraryVisible == false)
        #expect(appModel.isInspectorVisible == false)
        #expect(appModel.selectedInspectorTab == .ask)
        #expect(appModel.currentSelection == nil)
        #expect(appModel.savedHighlights.isEmpty)
    }

    @Test
    func selectionEnablesContextualActionsAndHighlightCapture() throws {
        let noteStore = StubNoteStore()
        let appModel = AppModel(
            documentAssistant: StubDocumentAssistant(result: "Unused"),
            knowledgeCapture: StubKnowledgeCapture(),
            noteStore: noteStore
        )
        appModel.importDocument(from: URL(fileURLWithPath: "/tmp/Transformer Notes.pdf"))

        let selection = DocumentSelection(
            text: "Transformers replaced recurrence with attention.",
            pageIndex: 12,
            surroundingText: "The paper describes multi-head attention and parallel training improvements."
        )

        appModel.updateCurrentSelection(selection)
        appModel.noteDraft = "Core architecture breakthrough"

        try appModel.saveHighlightFromSelection()

        #expect(appModel.currentSelection == selection)
        #expect(appModel.hasActiveSelection)
        #expect(appModel.savedHighlights.count == 1)
        #expect(appModel.savedHighlights[0].quotedText == selection.text)
        #expect(appModel.savedHighlights[0].pageIndex == 12)
        #expect(noteStore.savedNotes.count == 1)
        #expect(noteStore.savedNotes[0].title.contains("Highlight"))
        #expect(noteStore.savedNotes[0].highlightExcerpt == selection.text)
        #expect(appModel.noteDraft.isEmpty)
        #expect(appModel.isInspectorVisible)
        #expect(appModel.selectedInspectorTab == .highlights)
    }

    @Test
    func saveNotePersistsSelectionBackedMarkdownEntry() throws {
        let noteStore = StubNoteStore()
        let appModel = AppModel(
            documentAssistant: StubDocumentAssistant(result: "Unused"),
            knowledgeCapture: StubKnowledgeCapture(),
            noteStore: noteStore
        )
        appModel.importDocument(from: URL(fileURLWithPath: "/tmp/Designing Data Intensive Applications.pdf"))
        appModel.updateCurrentSelection(
            DocumentSelection(
                text: "State is the core problem in distributed systems.",
                pageIndex: 40,
                surroundingText: "The chapter explains why state and coordination dominate distributed system design."
            )
        )
        appModel.noteDraft = "Review this before implementing optimistic replication.\nCompare with CRDT chapter."

        try appModel.saveNote()

        #expect(noteStore.savedNotes.count == 1)
        #expect(noteStore.savedNotes[0].title.contains("Note"))
        #expect(noteStore.savedNotes[0].bulletPoints.count == 2)
        #expect(noteStore.savedNotes[0].highlightExcerpt == "State is the core problem in distributed systems.")
        #expect(appModel.savedNotes.count == 1)
        #expect(appModel.selectedInspectorTab == .notes)
        #expect(appModel.noteDraft.isEmpty)
    }

    @Test
    func quickHighlightPreservesInProgressNoteDraft() throws {
        let noteStore = StubNoteStore()
        let appModel = AppModel(
            documentAssistant: StubDocumentAssistant(result: "Unused"),
            knowledgeCapture: StubKnowledgeCapture(),
            noteStore: noteStore
        )
        appModel.importDocument(from: URL(fileURLWithPath: "/tmp/Bookmarked Systems.pdf"))
        appModel.updateCurrentSelection(
            DocumentSelection(
                text: "Backpressure protects downstream consumers.",
                pageIndex: 4,
                surroundingText: "The chapter explains bounded queues and admission control."
            )
        )
        appModel.noteDraft = "Draft note that should survive."

        try appModel.saveQuickHighlight()

        #expect(appModel.savedHighlights.count == 1)
        #expect(appModel.savedHighlights[0].noteText == nil)
        #expect(appModel.noteDraft == "Draft note that should survive.")
        #expect(noteStore.savedNotes[0].notePreview == nil)
    }

    @Test
    func epubHighlightUsesChapterCopyInSavedMetadata() throws {
        let noteStore = StubNoteStore()
        let appModel = AppModel(
            documentAssistant: StubDocumentAssistant(result: "Unused"),
            knowledgeCapture: StubKnowledgeCapture(),
            noteStore: noteStore
        )
        appModel.importDocument(from: URL(fileURLWithPath: "/tmp/Distributed Reading.epub"))
        appModel.updateCurrentSelection(
            DocumentSelection(
                text: "Quorum writes trade latency for stronger durability guarantees.",
                pageIndex: 1,
                surroundingText: "The chapter explains why quorum systems improve durability."
            )
        )

        try appModel.saveQuickHighlight()

        #expect(noteStore.savedNotes.count == 1)
        #expect(noteStore.savedNotes[0].bulletPoints.first == "Saved from chapter 2.")
    }

    @Test
    func capturePersistsPDFHighlights() async throws {
        let noteStore = StubNoteStore()
        let highlightStore = StubDocumentHighlightStore()
        let appModel = AppModel(
            documentAssistant: StubDocumentAssistant(result: "Unused"),
            knowledgeCapture: StubKnowledgeCapture(),
            noteStore: noteStore,
            highlightStore: highlightStore
        )
        let documentURL = URL(fileURLWithPath: "/tmp/Agentic Reader.pdf")
        appModel.importDocument(from: documentURL)

        let draft = PDFDocumentHighlightDraft(
            id: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!,
            pageIndex: 3,
            quotedText: "Agent loops need bounded memory and clear tool contracts.",
            color: .mint,
            rects: [
                CGRect(x: 40, y: 500, width: 180, height: 18),
                CGRect(x: 40, y: 478, width: 140, height: 18)
            ]
        )

        await appModel.capturePDFHighlights([draft])

        #expect(appModel.savedHighlights.count == 1)
        #expect(appModel.savedHighlights[0].color == .mint)
        #expect(appModel.savedHighlights[0].quotedText == draft.quotedText)
        #expect(appModel.pdfDocumentHighlights.count == 1)
        #expect(appModel.pdfDocumentHighlights[0].rects.count == 2)
        #expect(noteStore.savedNotes.count == 1)
        #expect(noteStore.savedNotes[0].id == draft.id)
        #expect(try highlightStore.loadHighlights(for: ReaderDocument(fileURL: documentURL)).count == 1)
    }

    @Test
    func deleteRemovesHighlight() async throws {
        let noteStore = StubNoteStore()
        let highlightStore = StubDocumentHighlightStore()
        let appModel = AppModel(
            documentAssistant: StubDocumentAssistant(result: "Unused"),
            knowledgeCapture: StubKnowledgeCapture(),
            noteStore: noteStore,
            highlightStore: highlightStore
        )
        let documentURL = URL(fileURLWithPath: "/tmp/Deletable Highlight.pdf")
        appModel.importDocument(from: documentURL)

        let draft = PDFDocumentHighlightDraft(
            id: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!,
            pageIndex: 0,
            quotedText: "Delete me when the highlight is no longer useful.",
            color: .yellow,
            rects: [CGRect(x: 32, y: 412, width: 220, height: 18)]
        )

        await appModel.capturePDFHighlights([draft])
        await appModel.deleteHighlight(draft.id)

        #expect(appModel.savedHighlights.isEmpty)
        #expect(appModel.pdfDocumentHighlights.isEmpty)
        #expect(noteStore.savedNotes.isEmpty)
        #expect(try highlightStore.loadHighlights(for: ReaderDocument(fileURL: documentURL)).isEmpty)
    }

    @Test
    func selectionScopesReaderState() async throws {
        let noteStore = StubNoteStore()
        let appModel = AppModel(
            documentAssistant: StubDocumentAssistant(result: "Unused"),
            knowledgeCapture: StubKnowledgeCapture(),
            noteStore: noteStore
        )

        appModel.importDocument(from: URL(fileURLWithPath: "/tmp/Book One.pdf"))
        appModel.providerStatuses = [
            AIProviderStatus(kind: .ollama, isAvailable: true, detail: "ready", models: ["llama3.2"])
        ]
        appModel.chatInput = "What matters here?"
        appModel.chatTranscript = [
            ChatMessage(role: .user, content: "Old thread"),
            ChatMessage(role: .assistant, content: "Old answer")
        ]
        appModel.noteDraft = "Carry over draft"
        appModel.savedHighlights = [
            ReaderHighlight(
                id: UUID(),
                documentTitle: "Book One",
                pageIndex: 0,
                quotedText: "Old quote",
                noteText: nil,
                createdAt: Date()
            )
        ]
        appModel.updateCurrentSelection(
            DocumentSelection(text: "Old quote", pageIndex: 0, surroundingText: "Old context")
        )
        appModel.updateReadingPosition(currentPageIndex: 5, visiblePageIndexes: [5, 6])
        try noteStore.save(
            note: KnowledgeNote(
                id: UUID(),
                kind: .highlight,
                title: "Book One Highlight",
                sourceIdentifier: "/tmp/Book One.pdf",
                createdAt: Date(),
                bulletPoints: ["Old note"],
                highlightExcerpt: "Old quote",
                pageIndex: 0,
                notePreview: "Old note"
            )
        )
        try noteStore.save(
            note: KnowledgeNote(
                id: UUID(),
                kind: .highlight,
                title: "Book Two Highlight",
                sourceIdentifier: "/tmp/Book Two.pdf",
                createdAt: Date().addingTimeInterval(1),
                bulletPoints: ["Fresh note"],
                highlightExcerpt: "Fresh quote",
                pageIndex: 9,
                notePreview: "Fresh note"
            )
        )

        appModel.selectDocument(ReaderDocument(fileURL: URL(fileURLWithPath: "/tmp/Book Two.pdf")))

        #expect(appModel.selectedDocument?.title == "Book Two")
        #expect(appModel.isLibraryVisible == false)
        #expect(appModel.currentSelection == nil)
        #expect(appModel.currentPageIndex == nil)
        #expect(appModel.visiblePageIndexes.isEmpty)
        #expect(appModel.chatInput.isEmpty)
        #expect(appModel.chatTranscript.isEmpty)
        #expect(appModel.noteDraft.isEmpty)
        #expect(appModel.savedNotes.count == 1)
        #expect(appModel.savedNotes[0].sourceIdentifier == "/tmp/Book Two.pdf")
        await waitUntil { appModel.savedHighlights.count == 1 }
        #expect(appModel.savedHighlights.count == 1)
        #expect(appModel.savedHighlights.first?.pageIndex == 9)
        #expect(appModel.savedHighlights.first?.quotedText == "Fresh quote")
    }

    @Test
    func prepareSelectionNoteSeedsStructuredTemplate() {
        let appModel = AppModel(
            documentAssistant: StubDocumentAssistant(result: "Unused"),
            knowledgeCapture: StubKnowledgeCapture(),
            noteStore: StubNoteStore()
        )
        appModel.importDocument(from: URL(fileURLWithPath: "/tmp/Pragmatic Programmer.pdf"))
        appModel.updateCurrentSelection(
            DocumentSelection(
                text: "The quality of the code from an expert is evident.",
                pageIndex: 7,
                surroundingText: "The chapter argues that craftsmanship compounds over time."
            )
        )

        appModel.prepareSelectionNote()

        #expect(appModel.isInspectorVisible)
        #expect(appModel.selectedInspectorTab == .notes)
        #expect(appModel.noteDraft.contains("Key idea:"))
        #expect(appModel.noteDraft.contains("Quote: The quality of the code from an expert is evident."))
    }

    @Test
    func currentPageLabelUsesChapterCopyForEPUBDocuments() {
        let appModel = AppModel(
            documentAssistant: StubDocumentAssistant(result: "Unused"),
            knowledgeCapture: StubKnowledgeCapture(),
            noteStore: StubNoteStore()
        )

        appModel.importDocument(from: URL(fileURLWithPath: "/tmp/Distributed Reading.epub"))
        appModel.updateReadingPosition(currentPageIndex: 2)

        #expect(appModel.currentPageLabel == "Chapter 3")
    }

    @Test
    func importingDocumentLoadsVisualsAndSelectsTheFirstOne() async {
        let firstVisual = DocumentVisualAsset(
            id: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!,
            pageIndex: 2,
            kind: .embeddedImage,
            imageData: Data([0x01, 0x02, 0x03]),
            pixelWidth: 640,
            pixelHeight: 480,
            suggestedFilename: "agents-page-3-figure-1.png"
        )
        let secondVisual = DocumentVisualAsset(
            id: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!,
            pageIndex: 4,
            kind: .pageSnapshot,
            imageData: Data([0x04, 0x05, 0x06]),
            pixelWidth: 1280,
            pixelHeight: 720,
            suggestedFilename: "agents-page-5-snapshot.png"
        )
        let appModel = AppModel(
            documentAssistant: StubDocumentAssistant(result: "Unused"),
            knowledgeCapture: StubKnowledgeCapture(),
            noteStore: StubNoteStore(),
            visualExtractor: StubVisualExtractor(visuals: [firstVisual, secondVisual])
        )

        appModel.importDocument(from: URL(fileURLWithPath: "/tmp/Agent Mesh.pdf"))
        await waitUntil { !appModel.isExtractingVisuals }

        #expect(appModel.documentVisuals == [firstVisual, secondVisual])
        #expect(appModel.selectedVisual?.id == firstVisual.id)
    }

    /// Re-activating the document mid-scan restarts the scan; the cancelled one
    /// must not clear the in-progress state or publish over its replacement.
    @Test
    func reactivatingSameDocumentKeepsReplacementScanInProgress() async {
        let visual = DocumentVisualAsset(
            id: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!,
            pageIndex: 2,
            kind: .embeddedImage,
            imageData: Data([0x01, 0x02, 0x03]),
            pixelWidth: 640,
            pixelHeight: 480,
            suggestedFilename: "agents-page-3-figure-1.png"
        )
        let extractor = GatedVisualExtractor(visuals: [visual])
        let appModel = AppModel(
            documentAssistant: StubDocumentAssistant(result: "Unused"),
            knowledgeCapture: StubKnowledgeCapture(),
            noteStore: StubNoteStore(),
            visualExtractor: extractor
        )
        let url = URL(fileURLWithPath: "/tmp/Agent Mesh.pdf")

        appModel.importDocument(from: url)
        await waitUntil { extractor.enteredCount == 1 }

        appModel.importDocument(from: url)
        await waitUntil { extractor.enteredCount == 2 }
        await waitUntil { extractor.cancelledCount == 1 }
        try? await Task.sleep(for: .milliseconds(100))

        #expect(appModel.isExtractingVisuals)

        extractor.release()
        await waitUntil { !appModel.isExtractingVisuals }

        #expect(appModel.documentVisuals == [visual])
    }

    @Test
    func explainVisualsUsesSelectedVisualWhenAvailable() async throws {
        let selectedVisual = DocumentVisualAsset(
            id: UUID(),
            pageIndex: 6,
            kind: .embeddedImage,
            imageData: Data([0xAA, 0xBB]),
            pixelWidth: 800,
            pixelHeight: 600,
            suggestedFilename: "mesh-page-7-figure.png"
        )
        let assistant = RecordingDocumentAssistant(result: "Diagram explained.")
        let appModel = AppModel(
            documentAssistant: assistant,
            knowledgeCapture: StubKnowledgeCapture(),
            noteStore: StubNoteStore(),
            visualExtractor: StubVisualExtractor(visuals: [selectedVisual]),
            visualExporter: StubVisualExporter()
        )
        appModel.providerStatuses = [
            AIProviderStatus(kind: .ollama, isAvailable: true, detail: "ready", models: ["llava:latest"])
        ]

        appModel.importDocument(from: URL(fileURLWithPath: "/tmp/Agent Mesh.pdf"))
        await waitUntil { !appModel.isExtractingVisuals }
        await appModel.runQuickAction(LearningAction.explainVisuals)

        #expect(appModel.chatTranscript.last?.content == "Diagram explained.")
        #expect(assistant.lastVisual?.id == selectedVisual.id)
    }

    @Test
    func explainVisualsFallsBackToCurrentPageSnapshot() async throws {
        let snapshot = DocumentVisualAsset(
            id: UUID(),
            pageIndex: 10,
            kind: .pageSnapshot,
            imageData: Data([0x10, 0x20]),
            pixelWidth: 1280,
            pixelHeight: 960,
            suggestedFilename: "agents-page-11-snapshot.png"
        )
        let assistant = RecordingDocumentAssistant(result: "Snapshot explained.")
        let appModel = AppModel(
            documentAssistant: assistant,
            knowledgeCapture: StubKnowledgeCapture(),
            noteStore: StubNoteStore(),
            visualExtractor: StubVisualExtractor(visuals: [], renderedSnapshot: snapshot),
            visualExporter: StubVisualExporter()
        )
        appModel.providerStatuses = [
            AIProviderStatus(kind: .ollama, isAvailable: true, detail: "ready", models: ["llava:latest"])
        ]

        appModel.importDocument(from: URL(fileURLWithPath: "/tmp/Agent Mesh.pdf"))
        await waitUntil { !appModel.isExtractingVisuals }
        appModel.selectedVisual = nil
        appModel.updateReadingPosition(currentPageIndex: 10)
        await appModel.runQuickAction(LearningAction.explainVisuals)

        #expect(appModel.chatTranscript.last?.content == "Snapshot explained.")
        #expect(assistant.lastVisual?.id == snapshot.id)
    }

    @Test
    func explainVisualsFallsBackToFirstExtractedVisualWhenSelectionIsMissing() async throws {
        let firstVisual = DocumentVisualAsset(
            id: UUID(),
            pageIndex: 2,
            kind: .embeddedImage,
            imageData: Data([0xFE, 0xED]),
            pixelWidth: 960,
            pixelHeight: 540,
            suggestedFilename: "agents-page-3-figure.png"
        )
        let assistant = RecordingDocumentAssistant(result: "First visual explained.")
        let appModel = AppModel(
            documentAssistant: assistant,
            knowledgeCapture: StubKnowledgeCapture(),
            noteStore: StubNoteStore(),
            visualExtractor: StubVisualExtractor(visuals: [firstVisual]),
            visualExporter: StubVisualExporter()
        )
        appModel.providerStatuses = [
            AIProviderStatus(kind: .ollama, isAvailable: true, detail: "ready", models: ["llava:latest"])
        ]

        appModel.importDocument(from: URL(fileURLWithPath: "/tmp/Agent Mesh.pdf"))
        await waitUntil { !appModel.isExtractingVisuals }
        appModel.selectedVisual = nil
        await appModel.runQuickAction(LearningAction.explainVisuals)

        #expect(appModel.chatTranscript.last?.content == "First visual explained.")
        #expect(assistant.lastVisual?.id == firstVisual.id)
        #expect(appModel.selectedVisual?.id == firstVisual.id)
    }

    @Test
    func exportSelectedVisualUsesVisualExporter() async throws {
        let exportedURL = URL(fileURLWithPath: "/tmp/exported-visual.png")
        let visual = DocumentVisualAsset(
            id: UUID(),
            pageIndex: 1,
            kind: .embeddedImage,
            imageData: Data([0xAB, 0xCD]),
            pixelWidth: 900,
            pixelHeight: 500,
            suggestedFilename: "agents-page-2-figure.png"
        )
        let exporter = StubVisualExporter(result: exportedURL)
        let appModel = AppModel(
            documentAssistant: StubDocumentAssistant(result: "Unused"),
            knowledgeCapture: StubKnowledgeCapture(),
            noteStore: StubNoteStore(),
            visualExtractor: StubVisualExtractor(visuals: [visual]),
            visualExporter: exporter
        )

        appModel.importDocument(from: URL(fileURLWithPath: "/tmp/Agent Mesh.pdf"))
        await waitUntil { !appModel.isExtractingVisuals }
        let exported = try appModel.exportSelectedVisual()

        #expect(exported == exportedURL)
        #expect(exporter.lastVisual?.id == visual.id)
    }

    @Test
    func exportSelectedVisualFallsBackToFirstVisualWhenSelectionIsMissing() async throws {
        let exportedURL = URL(fileURLWithPath: "/tmp/exported-first-visual.png")
        let visual = DocumentVisualAsset(
            id: UUID(),
            pageIndex: 5,
            kind: .pageSnapshot,
            imageData: Data([0xAA, 0x55]),
            pixelWidth: 1100,
            pixelHeight: 700,
            suggestedFilename: "agents-page-6-snapshot.png"
        )
        let exporter = StubVisualExporter(result: exportedURL)
        let appModel = AppModel(
            documentAssistant: StubDocumentAssistant(result: "Unused"),
            knowledgeCapture: StubKnowledgeCapture(),
            noteStore: StubNoteStore(),
            visualExtractor: StubVisualExtractor(visuals: [visual]),
            visualExporter: exporter
        )

        appModel.importDocument(from: URL(fileURLWithPath: "/tmp/Agent Mesh.pdf"))
        await waitUntil { !appModel.isExtractingVisuals }
        appModel.selectedVisual = nil
        let exported = try appModel.exportSelectedVisual()

        #expect(exported == exportedURL)
        #expect(exporter.lastVisual?.id == visual.id)
        #expect(appModel.selectedVisual?.id == visual.id)
    }
}

@MainActor
private final class StubNoteStore: KnowledgeNoteStoring {
    private(set) var savedNotes: [KnowledgeNote] = []

    func save(note: KnowledgeNote) throws {
        savedNotes.append(note)
    }

    func searchNotes(matching query: String, limit: Int) throws -> [KnowledgeNoteSummary] {
        savedNotes.compactMap { note in
            let searchableContent = [
                note.title,
                note.sourceIdentifier,
                note.highlightExcerpt ?? "",
                note.bulletPoints.joined(separator: "\n")
            ].joined(separator: "\n")

            guard query.isEmpty || searchableContent.localizedCaseInsensitiveContains(query) else {
                return nil
            }

            return KnowledgeNoteSummary(
                id: note.id,
                kind: note.kind,
                title: note.title,
                sourceIdentifier: note.sourceIdentifier,
                createdAt: note.createdAt,
                highlightExcerpt: note.highlightExcerpt,
                pageIndex: note.pageIndex,
                notePreview: note.notePreview,
                fileURL: URL(fileURLWithPath: "/tmp/\(note.id.uuidString).md")
            )
        }
    }

    func delete(noteID: UUID) throws {
        savedNotes.removeAll { $0.id == noteID }
    }
}

private struct StubDocumentAssistant: DocumentAssisting {
    let result: String

    func answer(
        question: String,
        for document: ReaderDocument,
        providerStatuses: [AIProviderStatus],
        scope: DocumentQueryScope,
        selection: DocumentSelection?,
        currentPageIndex: Int?,
        visiblePageIndexes: [Int],
        visualAsset: DocumentVisualAsset?,
        onProgress: @escaping @Sendable (DocumentAssistantProgress) -> Void
    ) async throws -> String {
        result
    }
}

@MainActor
private final class StubKnowledgeCapture: KnowledgeCapturing {
    func capture(question: String, answer: String, for document: ReaderDocument) throws {}
}

private final class GatedVisualExtractor: DocumentVisualExtracting, @unchecked Sendable {
    private let visuals: [DocumentVisualAsset]
    private let lock = NSLock()
    private var entered = 0
    private var cancelled = 0
    private var released = false

    init(visuals: [DocumentVisualAsset]) {
        self.visuals = visuals
    }

    var enteredCount: Int {
        lock.withLock { entered }
    }

    var cancelledCount: Int {
        lock.withLock { cancelled }
    }

    func release() {
        lock.withLock { released = true }
    }

    func extractVisuals(
        for document: ReaderDocument,
        isCancelled: @escaping @Sendable () -> Bool,
        onProgress: @escaping @Sendable (PageScanProgress) -> Void
    ) throws -> [DocumentVisualAsset] {
        lock.withLock { entered += 1 }

        while !lock.withLock({ released }) {
            if isCancelled() {
                lock.withLock { cancelled += 1 }
                throw CancellationError()
            }

            Thread.sleep(forTimeInterval: 0.005)
        }

        return visuals
    }

    func renderPageSnapshot(for document: ReaderDocument, pageIndex: Int) throws -> DocumentVisualAsset? {
        nil
    }
}

private struct StubVisualExtractor: DocumentVisualExtracting {
    let visuals: [DocumentVisualAsset]
    let renderedSnapshot: DocumentVisualAsset?

    init(visuals: [DocumentVisualAsset], renderedSnapshot: DocumentVisualAsset? = nil) {
        self.visuals = visuals
        self.renderedSnapshot = renderedSnapshot
    }

    func extractVisuals(
        for document: ReaderDocument,
        isCancelled: @escaping @Sendable () -> Bool,
        onProgress: @escaping @Sendable (PageScanProgress) -> Void
    ) throws -> [DocumentVisualAsset] {
        visuals
    }

    func renderPageSnapshot(for document: ReaderDocument, pageIndex: Int) throws -> DocumentVisualAsset? {
        renderedSnapshot ?? visuals.first { $0.pageIndex == pageIndex }
    }
}

@MainActor
private final class StubDocumentHighlightStore: DocumentHighlightStoring {
    private(set) var storedHighlights: [String: [PDFDocumentHighlight]] = [:]

    func loadHighlights(for document: ReaderDocument) throws -> [PDFDocumentHighlight] {
        storedHighlights[document.fileURL.path] ?? []
    }

    func upsertHighlight(_ highlight: PDFDocumentHighlight, for document: ReaderDocument) throws {
        var highlights = storedHighlights[document.fileURL.path] ?? []
        if let index = highlights.firstIndex(where: { $0.id == highlight.id }) {
            highlights[index] = highlight
        } else {
            highlights.insert(highlight, at: 0)
        }
        storedHighlights[document.fileURL.path] = highlights
    }

    func removeHighlight(id: UUID, for document: ReaderDocument) throws {
        storedHighlights[document.fileURL.path] = (storedHighlights[document.fileURL.path] ?? []).filter { $0.id != id }
    }
}

private final class StubVisualExporter: @unchecked Sendable, DocumentVisualExporting {
    private(set) var lastVisual: DocumentVisualAsset?
    private let result: URL

    init(result: URL = URL(fileURLWithPath: "/tmp/export.png")) {
        self.result = result
    }

    func exportPNG(_ visual: DocumentVisualAsset, for document: ReaderDocument) throws -> URL {
        lastVisual = visual
        return result
    }
}

private final class RecordingDocumentAssistant: @unchecked Sendable, DocumentAssisting {
    private(set) var lastVisual: DocumentVisualAsset?
    let result: String

    init(result: String) {
        self.result = result
    }

    func answer(
        question: String,
        for document: ReaderDocument,
        providerStatuses: [AIProviderStatus],
        scope: DocumentQueryScope,
        selection: DocumentSelection?,
        currentPageIndex: Int?,
        visiblePageIndexes: [Int],
        visualAsset: DocumentVisualAsset?,
        onProgress: @escaping @Sendable (DocumentAssistantProgress) -> Void
    ) async throws -> String {
        lastVisual = visualAsset
        return result
    }
}
