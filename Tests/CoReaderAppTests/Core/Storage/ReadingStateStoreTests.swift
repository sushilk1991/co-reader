import Foundation
import Testing
@testable import CoReaderApp

struct ReadingStateStoreTests {
    @Test
    func saveAndLoadRoundTripThroughFileCoordination() throws {
        let sandbox = try TemporarySandbox()
        defer { sandbox.cleanup() }
        let store = ReadingStateStore(fileURL: sandbox.directory.appending(path: "ReadingState.json"))
        let bookURL = sandbox.directory.appending(path: "Book.pdf")
        let state = ReadingState(documentURLs: [bookURL], activeDocumentURL: bookURL, positions: [bookURL.path: 12])

        try store.save(state)
        let loaded = try store.load()

        #expect(loaded.documentURLs == [bookURL])
        #expect(loaded.activeDocumentURL == bookURL)
        #expect(loaded.positions == [bookURL.path: 12])
    }

    @Test
    func loadReturnsEmptyStateWhenNoFileExists() throws {
        let sandbox = try TemporarySandbox()
        defer { sandbox.cleanup() }
        let store = ReadingStateStore(fileURL: sandbox.directory.appending(path: "ReadingState.json"))

        let loaded = try store.load()

        #expect(loaded.documentURLs.isEmpty)
        #expect(loaded.activeDocumentURL == nil)
    }
}
