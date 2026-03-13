import Foundation

struct KnowledgeNoteSummary: Equatable, Sendable {
    let id: UUID
    let title: String
    let sourceIdentifier: String
    let createdAt: Date
    let highlightExcerpt: String?
    let fileURL: URL
}
