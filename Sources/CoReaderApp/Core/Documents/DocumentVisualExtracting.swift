protocol DocumentVisualExtracting: Sendable {
    func extractVisuals(for document: ReaderDocument) throws -> [DocumentVisualAsset]
    func renderPageSnapshot(for document: ReaderDocument, pageIndex: Int) throws -> DocumentVisualAsset?
}
