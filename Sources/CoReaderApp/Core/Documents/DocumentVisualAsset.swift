import Foundation

struct DocumentVisualAsset: Equatable, Identifiable, Sendable {
    let id: UUID
    let pageIndex: Int
    let kind: DocumentVisualKind
    let imageData: Data
    let pixelWidth: Int
    let pixelHeight: Int
    let suggestedFilename: String
}
