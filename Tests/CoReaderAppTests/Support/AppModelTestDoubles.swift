import Foundation
@testable import CoReaderApp

/// Shared test doubles for `AppModel` tests that live outside
/// `AppModelReaderStateTests.swift` (whose stubs are file-private).
@MainActor
final class InMemoryNoteStore: KnowledgeNoteStoring {
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

            return summary(for: note)
        }
    }

    func delete(noteID: UUID) throws {
        savedNotes.removeAll { $0.id == noteID }
    }

    private func summary(for note: KnowledgeNote) -> KnowledgeNoteSummary {
        KnowledgeNoteSummary(
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

struct FixedAnswerAssistant: DocumentAssisting {
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
final class NoOpKnowledgeCaptureDouble: KnowledgeCapturing {
    func capture(question: String, answer: String, for document: ReaderDocument) throws {}
}

struct EmptyVisualExtractor: DocumentVisualExtracting {
    func extractVisuals(
        for document: ReaderDocument,
        isCancelled: @escaping @Sendable () -> Bool,
        onProgress: @escaping @Sendable (PageScanProgress) -> Void
    ) throws -> [DocumentVisualAsset] {
        []
    }

    func renderPageSnapshot(for document: ReaderDocument, pageIndex: Int) throws -> DocumentVisualAsset? {
        nil
    }
}

/// Assistant whose every call fails; used to check that background features report errors.
struct ThrowingAssistant: DocumentAssisting {
    let message: String

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
        throw NSError(domain: "CoReader.Tests", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}

/// Failing assistant that counts its calls, for checking that a page is attempted once.
@MainActor
final class CountingThrowingAssistant: DocumentAssisting {
    private(set) var callCount = 0
    private let message: String

    init(message: String) {
        self.message = message
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
        callCount += 1
        throw NSError(domain: "CoReader.Tests", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}

/// Holds every answer until `release()`. What a cancelled wait does mirrors the
/// real providers: `BlockingWork`/`ProcessCommandRunner` throw `CancellationError`,
/// `URLSession` throws `URLError(.cancelled)`, and a provider that already finished
/// completes anyway.
@MainActor
final class GatedAssistant: DocumentAssisting {
    enum CancellationBehaviour {
        case throwsCancellationError
        case throwsURLCancelled
        case completesAnyway
    }

    private(set) var callCount = 0
    private var isReleased = false
    private let result: String
    private let cancellation: CancellationBehaviour

    init(result: String, cancellation: CancellationBehaviour = .throwsCancellationError) {
        self.result = result
        self.cancellation = cancellation
    }

    func release() {
        isReleased = true
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
        callCount += 1
        while !isReleased {
            do {
                try await Task.sleep(for: .milliseconds(5))
            } catch {
                switch cancellation {
                case .throwsCancellationError:
                    throw error
                case .throwsURLCancelled:
                    throw URLError(.cancelled)
                case .completesAnyway:
                    await Task.yield()
                }
            }
        }

        return result
    }
}

/// Polls `condition` until it holds or `timeout` passes, for work the model finishes
/// on a later main-actor turn (visual extraction, auto-summary).
@MainActor
func waitUntil(
    timeout: Duration = .seconds(5),
    _ condition: @MainActor () -> Bool
) async {
    let clock = ContinuousClock()
    let deadline = clock.now + timeout

    while !condition(), clock.now < deadline {
        try? await Task.sleep(for: .milliseconds(10))
    }
}
