import Foundation

struct KnowledgeNote: Equatable, Sendable {
    let id: UUID
    let title: String
    let sourceIdentifier: String
    let createdAt: Date
    let bulletPoints: [String]
    let highlightExcerpt: String?
}
