import Foundation
import Testing
@testable import CoReaderApp

@MainActor
struct AppModelNoteScopingTests {
    /// Two documents that share a filename must not share a notes list.
    @Test
    func notesAreScopedByFullPathNotFilename() throws {
        let noteStore = InMemoryNoteStore()
        let appModel = AppModel(
            documentAssistant: FixedAnswerAssistant(result: "Unused"),
            knowledgeCapture: NoOpKnowledgeCaptureDouble(),
            noteStore: noteStore,
            visualExtractor: EmptyVisualExtractor()
        )
        let firstURL = URL(fileURLWithPath: "/tmp/alpha/Notes.pdf")
        let secondURL = URL(fileURLWithPath: "/tmp/beta/Notes.pdf")

        appModel.importDocument(from: firstURL)
        appModel.updateCurrentSelection(
            DocumentSelection(text: "First book quote", pageIndex: 1, surroundingText: "Alpha context")
        )
        try appModel.saveQuickHighlight()

        appModel.importDocument(from: secondURL)
        appModel.updateCurrentSelection(
            DocumentSelection(text: "Second book quote", pageIndex: 2, surroundingText: "Beta context")
        )
        try appModel.saveQuickHighlight()

        #expect(appModel.savedNotes.map(\.highlightExcerpt) == ["Second book quote"])

        let firstDocument = try #require(appModel.importedDocuments.first { $0.fileURL == firstURL })
        appModel.selectDocument(firstDocument)

        #expect(appModel.savedNotes.map(\.highlightExcerpt) == ["First book quote"])
        #expect(noteStore.savedNotes.map(\.sourceIdentifier) == [firstURL.path, secondURL.path])
    }
}
