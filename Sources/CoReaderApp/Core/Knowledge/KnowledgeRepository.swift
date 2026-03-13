import Foundation

struct KnowledgeRepository {
    let markdownStore: MarkdownKnowledgeStore
    let index: SQLiteKnowledgeIndex

    init(markdownStore: MarkdownKnowledgeStore, index: SQLiteKnowledgeIndex) throws {
        self.markdownStore = markdownStore
        self.index = index
    }

    func save(note: KnowledgeNote) throws {
        let fileURL = try markdownStore.save(note: note)
        try index.upsert(note: note, fileURL: fileURL)
    }

    func noteFileURL(for note: KnowledgeNote) -> URL {
        markdownStore.noteFileURL(for: note)
    }

    func searchNotes(matching query: String, limit: Int = 20) throws -> [KnowledgeNoteSummary] {
        try index.search(matching: query, limit: limit)
    }
}
