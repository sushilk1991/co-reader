import Foundation

@MainActor
protocol KnowledgeNoteStoring {
    func save(note: KnowledgeNote) throws
    func searchNotes(matching query: String, limit: Int) throws -> [KnowledgeNoteSummary]
    /// Exact match on `sourceIdentifier`; a substring search would mix documents.
    func notes(forSource sourceIdentifier: String, limit: Int) throws -> [KnowledgeNoteSummary]
    func delete(noteID: UUID) throws
    /// Re-derives the search index from the markdown files. Returns the number of
    /// rows added or removed.
    func rebuildIndexFromMarkdown() async throws -> Int
}

extension KnowledgeNoteStoring {
    /// Stores without an exact-source query filter a broad search instead.
    func notes(forSource sourceIdentifier: String, limit: Int) throws -> [KnowledgeNoteSummary] {
        let broadSearchLimit = 1_000
        return Array(
            try searchNotes(matching: "", limit: broadSearchLimit)
                .filter { $0.sourceIdentifier == sourceIdentifier }
                .prefix(limit)
        )
    }

    func rebuildIndexFromMarkdown() async throws -> Int {
        0
    }
}

extension KnowledgeRepository: KnowledgeNoteStoring {}
