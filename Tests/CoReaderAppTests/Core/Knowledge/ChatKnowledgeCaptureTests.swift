import Foundation
import Testing
@testable import CoReaderApp

struct ChatKnowledgeCaptureTests {
    @MainActor
    @Test
    func captureWritesMarkdownAndSearchableMetadata() throws {
        let environment = try TemporaryKnowledgeEnvironment()
        defer { environment.cleanup() }

        let repository = try environment.makeRepository()
        let captureService = ChatKnowledgeCapture(repository: repository)
        let document = ReaderDocument(fileURL: URL(fileURLWithPath: "/tmp/Distributed Systems.pdf"))

        try captureService.capture(
            question: "What is consensus?",
            answer: "Consensus coordinates replicas and prevents split brain. It also makes failure recovery predictable.",
            for: document
        )

        let results = try repository.searchNotes(matching: "split brain")

        #expect(results.count == 1)
        #expect(results.first?.title.contains("Distributed Systems") == true)

        let note = try String(contentsOf: results[0].fileURL, encoding: .utf8)
        #expect(note.contains("What is consensus?"))
        #expect(note.contains("Consensus coordinates replicas"))
    }
}

private struct TemporaryKnowledgeEnvironment {
    let rootDirectory: URL

    init() throws {
        rootDirectory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
    }

    func makeRepository() throws -> KnowledgeRepository {
        try KnowledgeRepository(
            markdownStore: MarkdownKnowledgeStore(
                baseDirectory: rootDirectory.appending(path: "notes", directoryHint: .isDirectory)
            ),
            index: SQLiteKnowledgeIndex(
                databaseURL: rootDirectory.appending(path: "knowledge.sqlite")
            )
        )
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: rootDirectory)
    }
}
