protocol DocumentVisualExtracting: Sendable {
    /// Blocking. Callers run it through `BlockingWork`; implementations poll
    /// `isCancelled` between pages and report each finished page to `onProgress`.
    func extractVisuals(
        for document: ReaderDocument,
        isCancelled: @escaping @Sendable () -> Bool,
        onProgress: @escaping @Sendable (PageScanProgress) -> Void
    ) throws -> [DocumentVisualAsset]

    func renderPageSnapshot(for document: ReaderDocument, pageIndex: Int) throws -> DocumentVisualAsset?
}
