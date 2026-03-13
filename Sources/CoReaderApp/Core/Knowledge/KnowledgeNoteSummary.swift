import Foundation

struct KnowledgeNoteSummary: Equatable, Sendable {
    let id: UUID
    let kind: KnowledgeNoteKind
    let title: String
    let sourceIdentifier: String
    let createdAt: Date
    let highlightExcerpt: String?
    let pageIndex: Int?
    let notePreview: String?
    let fileURL: URL
}
