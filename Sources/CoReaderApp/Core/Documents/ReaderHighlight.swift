import Foundation

struct ReaderHighlight: Equatable, Identifiable, Sendable {
    let id: UUID
    let documentTitle: String
    let pageIndex: Int
    let quotedText: String
    let noteText: String?
    let createdAt: Date
}
