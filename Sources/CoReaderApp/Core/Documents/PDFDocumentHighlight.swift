import CoreGraphics
import Foundation

struct PDFDocumentHighlight: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let pageIndex: Int
    let quotedText: String
    let noteText: String?
    let createdAt: Date
    let color: ReaderHighlightColor
    let rects: [HighlightRect]

    struct HighlightRect: Codable, Equatable, Sendable {
        let x: Double
        let y: Double
        let width: Double
        let height: Double

        init(rect: CGRect) {
            x = rect.origin.x
            y = rect.origin.y
            width = rect.width
            height = rect.height
        }

        var cgRect: CGRect {
            CGRect(x: x, y: y, width: width, height: height)
        }

        var quadrilateralPoints: [CGPoint] {
            [
                CGPoint(x: x, y: y + height),
                CGPoint(x: x + width, y: y + height),
                CGPoint(x: x, y: y),
                CGPoint(x: x + width, y: y)
            ]
        }
    }
}

struct PDFDocumentHighlightDraft: Equatable, Sendable {
    let id: UUID
    let pageIndex: Int
    let quotedText: String
    let color: ReaderHighlightColor
    let rects: [CGRect]
}
