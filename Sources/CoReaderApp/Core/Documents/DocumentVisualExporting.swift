import Foundation

protocol DocumentVisualExporting: Sendable {
    func exportPNG(_ visual: DocumentVisualAsset, for document: ReaderDocument) throws -> URL
}
