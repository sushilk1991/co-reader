@MainActor
protocol KnowledgeNoteStoring {
    func save(note: KnowledgeNote) throws
    func searchNotes(matching query: String, limit: Int) throws -> [KnowledgeNoteSummary]
}

extension KnowledgeRepository: KnowledgeNoteStoring {}
