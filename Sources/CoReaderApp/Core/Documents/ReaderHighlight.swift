import Foundation

struct ReaderHighlight: Equatable, Identifiable, Sendable {
    let id: UUID
    let documentTitle: String
    let pageIndex: Int
    let quotedText: String
    let noteText: String?
    let createdAt: Date
    let color: ReaderHighlightColor

    init(
        id: UUID,
        documentTitle: String,
        pageIndex: Int,
        quotedText: String,
        noteText: String?,
        createdAt: Date,
        color: ReaderHighlightColor = .yellow
    ) {
        self.id = id
        self.documentTitle = documentTitle
        self.pageIndex = pageIndex
        self.quotedText = quotedText
        self.noteText = noteText
        self.createdAt = createdAt
        self.color = color
    }
}
