import Foundation
import Testing
@testable import CoReaderApp

@MainActor
struct AppModelReadingStateTests {
    /// Saved page must come back after a relaunch: this was the "reading position
    /// never restored" bug, where the view published page 0 over the saved value.
    @Test
    func readingPositionRoundTripsThroughTheStateFile() async throws {
        let sandbox = try TemporarySandbox()
        defer { sandbox.cleanup() }
        let store = ReadingStateStore(fileURL: sandbox.directory.appending(path: "ReadingState.json"))
        let bookURL = try sandbox.touch("Book.pdf")

        let firstLaunch = makeAppModel(readingStateStore: store)
        await firstLaunch.restoreReadingStateIfNeeded()
        firstLaunch.importDocument(from: bookURL)
        firstLaunch.updateReadingPosition(currentPageIndex: 7, visiblePageIndexes: [7, 8])
        firstLaunch.saveReadingStateNow()

        let secondLaunch = makeAppModel(readingStateStore: store)
        #expect(secondLaunch.importedDocuments.isEmpty)

        await secondLaunch.restoreReadingStateIfNeeded()

        let restored = try #require(secondLaunch.selectedDocument)
        #expect(restored.fileURL == bookURL.standardizedFileURL)
        #expect(secondLaunch.currentPageIndex == 7)
        #expect(secondLaunch.readingPosition(for: restored) == 7)
    }

    @Test
    func restoreKeepsLibraryOrderAcrossLaunches() async throws {
        let sandbox = try TemporarySandbox()
        defer { sandbox.cleanup() }
        let store = ReadingStateStore(fileURL: sandbox.directory.appending(path: "ReadingState.json"))
        let older = try sandbox.touch("Older.pdf")
        let newer = try sandbox.touch("Newer.pdf")

        let firstLaunch = makeAppModel(readingStateStore: store)
        await firstLaunch.restoreReadingStateIfNeeded()
        firstLaunch.importDocument(from: older)
        firstLaunch.importDocument(from: newer)
        firstLaunch.saveReadingStateNow()

        let secondLaunch = makeAppModel(readingStateStore: store)
        await secondLaunch.restoreReadingStateIfNeeded()

        #expect(secondLaunch.importedDocuments.map(\.fileURL) == [newer, older].map(\.standardizedFileURL))
    }

    /// A file that has moved must be reported, not silently dropped.
    @Test
    func restoreReportsMissingFilesInsteadOfDroppingThemSilently() async throws {
        let sandbox = try TemporarySandbox()
        defer { sandbox.cleanup() }
        let store = ReadingStateStore(fileURL: sandbox.directory.appending(path: "ReadingState.json"))
        let present = try sandbox.touch("Present.pdf")
        let missing = sandbox.directory.appending(path: "Moved Away.pdf")
        try store.save(
            ReadingState(
                documentURLs: [present, missing],
                activeDocumentURL: missing,
                positions: [missing.path: 3]
            )
        )

        let appModel = makeAppModel(readingStateStore: store)
        await appModel.restoreReadingStateIfNeeded()

        #expect(appModel.importedDocuments.map(\.fileURL) == [present.standardizedFileURL])
        #expect(appModel.missingLibraryFiles == [missing])
        #expect(appModel.sessionNotice?.contains("Moved Away.pdf") == true)

        appModel.dismissSessionNotice()

        #expect(appModel.sessionNotice == nil)
    }

    @Test
    func restoreReportsUnreadableStateFile() async throws {
        let sandbox = try TemporarySandbox()
        defer { sandbox.cleanup() }
        let stateURL = sandbox.directory.appending(path: "ReadingState.json")
        try Data("not json".utf8).write(to: stateURL)

        let appModel = makeAppModel(readingStateStore: ReadingStateStore(fileURL: stateURL))
        await appModel.restoreReadingStateIfNeeded()

        #expect(appModel.sessionNotice?.contains("Could not restore") == true)
    }

    /// A failed auto-summary must say why instead of leaving the card blank.
    @Test
    func autoSummaryFailureIsVisible() async throws {
        let appModel = AppModel(
            documentAssistant: ThrowingAssistant(message: "Ollama generation failed."),
            knowledgeCapture: NoOpKnowledgeCaptureDouble(),
            noteStore: InMemoryNoteStore(),
            visualExtractor: EmptyVisualExtractor(),
            autoSummaryDelay: .zero
        )
        appModel.providerStatuses = [
            AIProviderStatus(kind: .ollama, isAvailable: true, detail: "ready", models: ["llama3.2"])
        ]
        appModel.importDocument(from: URL(fileURLWithPath: "/tmp/Summaries.pdf"))

        appModel.updateReadingPosition(currentPageIndex: 2, visiblePageIndexes: [2])
        await waitUntil { appModel.autoSummaryError != nil }

        #expect(appModel.autoSummaryError == "Auto-summary failed: Ollama generation failed.")
        #expect(appModel.autoSummary == nil)

        appModel.dismissAutoSummary()

        #expect(appModel.autoSummaryError == nil)
    }

    private func makeAppModel(readingStateStore: ReadingStateStore) -> AppModel {
        AppModel(
            documentAssistant: FixedAnswerAssistant(result: "Unused"),
            knowledgeCapture: NoOpKnowledgeCaptureDouble(),
            noteStore: InMemoryNoteStore(),
            visualExtractor: EmptyVisualExtractor(),
            readingStateStore: readingStateStore
        )
    }
}

struct TemporarySandbox {
    let directory: URL

    init() throws {
        directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func touch(_ name: String) throws -> URL {
        let url = directory.appending(path: name)
        try Data().write(to: url)
        return url
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: directory)
    }
}
