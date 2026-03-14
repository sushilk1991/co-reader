import Foundation

@MainActor
protocol KnowledgeNoteStoring {
    func save(note: KnowledgeNote) throws
    func searchNotes(matching query: String, limit: Int) throws -> [KnowledgeNoteSummary]
    func delete(noteID: UUID) throws
}

extension KnowledgeRepository: KnowledgeNoteStoring {}
