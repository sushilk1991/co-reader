import Foundation
import Testing
@testable import CoReaderApp

struct KnowledgeIndexRebuildTests {
    /// Notes synced as markdown to a second Mac must become searchable there even
    /// though the SQLite index is local-only.
    @Test
    @MainActor
    func rebuildMakesSyncedMarkdownNotesSearchable() async throws {
        let root = try TemporarySandbox()
        defer { root.cleanup() }
        let notesDirectory = root.directory.appending(path: "Notes", directoryHint: .isDirectory)
        let firstMac = try makeRepository(notesDirectory: notesDirectory, indexName: "first.sqlite")
        let highlight = KnowledgeNote(
            id: UUID(uuidString: "AAAAAAAA-0000-0000-0000-000000000001")!,
            kind: .highlight,
            title: "Consensus Highlight",
            sourceIdentifier: "/Users/reader/Books/Consensus.pdf",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            bulletPoints: ["Saved from page 4.", "Raft elects a leader per term."],
            highlightExcerpt: "Raft elects a leader per term.",
            pageIndex: 3,
            notePreview: nil
        )
        let note = KnowledgeNote(
            id: UUID(uuidString: "AAAAAAAA-0000-0000-0000-000000000002")!,
            kind: .note,
            title: "Consensus Note",
            sourceIdentifier: "/Users/reader/Books/Consensus.pdf",
            createdAt: Date(timeIntervalSince1970: 1_700_000_100),
            bulletPoints: ["Key idea: terms are monotonic.", "Why it matters: stale leaders step down."],
            highlightExcerpt: "terms",
            pageIndex: 5,
            notePreview: "Key idea: terms are monotonic.\nWhy it matters: stale leaders step down."
        )
        try firstMac.save(note: highlight)
        try firstMac.save(note: note)

        let secondMac = try makeRepository(notesDirectory: notesDirectory, indexName: "second.sqlite")
        #expect(try secondMac.searchNotes(matching: "raft").isEmpty)

        let changes = try await secondMac.rebuildIndexFromMarkdown()

        #expect(changes == 2)
        let results = try secondMac.notes(forSource: "/Users/reader/Books/Consensus.pdf")
        #expect(results.map(\.id) == [note.id, highlight.id])
        let rebuiltHighlight = try #require(results.last)
        #expect(rebuiltHighlight.kind == .highlight)
        #expect(rebuiltHighlight.pageIndex == 3)
        #expect(rebuiltHighlight.highlightExcerpt == "Raft elects a leader per term.")
        #expect(rebuiltHighlight.createdAt == highlight.createdAt)
        #expect(results.first?.notePreview == note.notePreview)
        #expect(try await secondMac.rebuildIndexFromMarkdown() == 0)
    }

    @Test
    @MainActor
    func rebuildDropsIndexRowsWhoseMarkdownIsGone() async throws {
        let root = try TemporarySandbox()
        defer { root.cleanup() }
        let notesDirectory = root.directory.appending(path: "Notes", directoryHint: .isDirectory)
        let repository = try makeRepository(notesDirectory: notesDirectory, indexName: "index.sqlite")
        let note = KnowledgeNote(
            id: UUID(),
            kind: .aiChat,
            title: "Chat",
            sourceIdentifier: "/tmp/Book.pdf",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            bulletPoints: ["Answer line."],
            highlightExcerpt: "Question?",
            pageIndex: nil,
            notePreview: "Answer line."
        )
        try repository.save(note: note)
        try FileManager.default.removeItem(at: repository.noteFileURL(for: note))

        let changes = try await repository.rebuildIndexFromMarkdown()

        #expect(changes == 1)
        #expect(try repository.searchNotes(matching: "answer").isEmpty)
    }

    @Test
    func markdownRoundTripsEveryField() throws {
        let root = try TemporarySandbox()
        defer { root.cleanup() }
        let store = MarkdownKnowledgeStore(baseDirectory: root.directory)
        let note = KnowledgeNote(
            id: UUID(uuidString: "BBBBBBBB-0000-0000-0000-000000000001")!,
            kind: .aiChat,
            title: "Paper AI Chat",
            sourceIdentifier: "/Users/reader/Paper.pdf",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            bulletPoints: ["First takeaway.", "Second takeaway."],
            highlightExcerpt: "What is the main claim?",
            pageIndex: nil,
            notePreview: "First takeaway."
        )
        let fileURL = try store.save(note: note)

        let loaded = try store.loadNotes()

        #expect(loaded.map(\.note) == [note])
        #expect(loaded.map { $0.fileURL.resolvingSymlinksInPath() } == [fileURL.resolvingSymlinksInPath()])
    }

    private func makeRepository(notesDirectory: URL, indexName: String) throws -> KnowledgeRepository {
        try KnowledgeRepository(
            markdownStore: MarkdownKnowledgeStore(baseDirectory: notesDirectory),
            index: SQLiteKnowledgeIndex(databaseURL: notesDirectory.deletingLastPathComponent().appending(path: indexName))
        )
    }
}
