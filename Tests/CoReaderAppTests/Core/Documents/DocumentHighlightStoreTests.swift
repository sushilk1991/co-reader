import Foundation
import Testing
@testable import CoReaderApp

@MainActor
struct DocumentHighlightStoreTests {
    /// Reading synced highlight bytes must never occupy the UI thread.
    @Test
    func readsLeaveMainActor() async throws {
        let sandbox = try TemporarySandbox()
        defer { sandbox.cleanup() }
        let document = ReaderDocument(fileURL: sandbox.directory.appending(path: "Book.pdf"))
        let store = LiveDocumentHighlightStore(baseDirectory: sandbox.directory, readData: { url in
            #expect(!Thread.isMainThread)
            return try Data(contentsOf: url)
        })
        let highlight = makeHighlight()
        try await store.upsertHighlight(highlight, for: document)

        let loaded = try await store.loadHighlights(for: document)

        #expect(loaded == [highlight])
    }

    /// A dataless cloud file must request download without reading bytes or overwriting existing highlights.
    @Test
    func placeholderRejectsEdits() async throws {
        let sandbox = try TemporarySandbox()
        defer { sandbox.cleanup() }
        let document = ReaderDocument(fileURL: sandbox.directory.appending(path: "Book.pdf"))
        let local = LiveDocumentHighlightStore(baseDirectory: sandbox.directory)
        let highlight = makeHighlight()
        try await local.upsertHighlight(highlight, for: document)
        let storedFile = try #require(FileManager.default.contentsOfDirectory(
            at: sandbox.directory, includingPropertiesForKeys: nil
        ).first)
        let original = try Data(contentsOf: storedFile)
        let downloads = DownloadRequests()
        let placeholder = LiveDocumentHighlightStore(
            baseDirectory: sandbox.directory,
            readData: { _ in
                Issue.record("A placeholder must not be opened before download.")
                return Data()
            },
            cloudStatus: { _ in .notDownloaded },
            requestDownload: { downloads.record($0) }
        )

        do {
            _ = try await placeholder.loadHighlights(for: document)
            Issue.record("Expected a pending-download error.")
        } catch {
            #expect(error.localizedDescription.contains("still downloading from iCloud"))
        }
        await #expect(throws: (any Error).self) {
            try await placeholder.upsertHighlight(makeHighlight(), for: document)
        }
        await #expect(throws: (any Error).self) {
            try await placeholder.removeHighlight(id: highlight.id, for: document)
        }

        #expect(downloads.urls.map { $0.resolvingSymlinksInPath() } == Array(repeating: storedFile.resolvingSymlinksInPath(), count: 3))
        #expect(try Data(contentsOf: storedFile) == original)
        #expect(try await local.loadHighlights(for: document) == [highlight])
    }

    /// Moving edits off the actor must preserve both highlights when callers overlap.
    @Test
    func concurrentEditsPreserveBoth() async throws {
        let sandbox = try TemporarySandbox()
        defer { sandbox.cleanup() }
        let document = ReaderDocument(fileURL: sandbox.directory.appending(path: "Book.pdf"))
        let store = LiveDocumentHighlightStore(baseDirectory: sandbox.directory)
        let first = makeHighlight()
        let second = makeHighlight()

        async let firstSave: Void = store.upsertHighlight(first, for: document)
        async let secondSave: Void = store.upsertHighlight(second, for: document)
        _ = try await (firstSave, secondSave)
        let saved = try await store.loadHighlights(for: document)
        #expect(Set(saved.map(\.id)) == [first.id, second.id])

        try await store.removeHighlight(id: first.id, for: document)
        #expect(try await store.loadHighlights(for: document) == [second])
    }

    /// Use whole seconds to match the persisted ISO-8601 date representation.
    private func makeHighlight() -> PDFDocumentHighlight {
        PDFDocumentHighlight(
            id: UUID(), pageIndex: 2, quotedText: "A passage", noteText: nil,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000), color: .mint,
            rects: [.init(rect: CGRect(x: 10, y: 20, width: 100, height: 30))]
        )
    }
}

/// Observe download requests from the GCD worker without racing the main-actor assertion.
private final class DownloadRequests: @unchecked Sendable {
    private let lock = NSLock()
    private var requests: [URL] = []

    var urls: [URL] {
        lock.withLock { requests }
    }

    func record(_ url: URL) {
        #expect(!Thread.isMainThread)
        lock.withLock { requests.append(url) }
    }
}
