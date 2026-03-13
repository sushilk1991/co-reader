import Foundation
import Testing
@testable import CoReaderApp

struct KnowledgeRepositoryTests {
    @Test
    func saveWritesMarkdownAndIndexesMetadata() throws {
        let environment = try TestKnowledgeEnvironment()
        defer { environment.cleanup() }

        let repository = try environment.makeRepository()
        let note = KnowledgeNote(
            id: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!,
            kind: .highlight,
            title: "Ollama Primer",
            sourceIdentifier: "chapter-1",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            bulletPoints: [
                "Local models keep document context private.",
                "Probe localhost:11434 before showing model actions."
            ],
            highlightExcerpt: "Ollama exposes model tags via /api/tags.",
            pageIndex: 3,
            notePreview: "Local models keep document context private."
        )

        try repository.save(note: note)

        let markdown = try String(contentsOf: repository.noteFileURL(for: note), encoding: .utf8)
        let results = try repository.searchNotes(matching: "localhost")

        #expect(markdown.contains("# Ollama Primer"))
        #expect(markdown.contains("- Local models keep document context private."))
        #expect(results.count == 1)
        #expect(results.first?.title == "Ollama Primer")
        #expect(results.first?.sourceIdentifier == "chapter-1")
        #expect(results.first?.kind == .highlight)
        #expect(results.first?.pageIndex == 3)
        #expect(results.first?.notePreview == "Local models keep document context private.")
    }

    @Test
    func searchReturnsRecentMatchingNotes() throws {
        let environment = try TestKnowledgeEnvironment()
        defer { environment.cleanup() }

        let repository = try environment.makeRepository()
        let olderNote = KnowledgeNote(
            id: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!,
            kind: .note,
            title: "Local inference baseline",
            sourceIdentifier: "pdf-1",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            bulletPoints: ["Local inference avoids upload latency."],
            highlightExcerpt: nil,
            pageIndex: nil,
            notePreview: "Local inference avoids upload latency."
        )
        let newerNote = KnowledgeNote(
            id: UUID(uuidString: "66666666-7777-8888-9999-AAAAAAAAAAAA")!,
            kind: .highlight,
            title: "Local indexing pipeline",
            sourceIdentifier: "pdf-2",
            createdAt: Date(timeIntervalSince1970: 1_700_000_100),
            bulletPoints: ["Local note indexes should stay searchable."],
            highlightExcerpt: "SQLite makes local lookups predictable.",
            pageIndex: 11,
            notePreview: "Local note indexes should stay searchable."
        )

        try repository.save(note: olderNote)
        try repository.save(note: newerNote)

        let results = try repository.searchNotes(matching: "local")

        #expect(results.map(\.title) == ["Local indexing pipeline", "Local inference baseline"])
    }
}

private struct TestKnowledgeEnvironment {
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
