protocol DocumentContextExtracting: Sendable {
    /// Blocking. Callers run it through `BlockingWork`; implementations poll
    /// `isCancelled` between pages and report each finished page to `onProgress`.
    func extractContext(
        for document: ReaderDocument,
        question: String,
        scope: DocumentQueryScope,
        selection: DocumentSelection?,
        currentPageIndex: Int?,
        visiblePageIndexes: [Int],
        isCancelled: @escaping @Sendable () -> Bool,
        onProgress: @escaping @Sendable (PageScanProgress) -> Void
    ) throws -> DocumentContext
}

extension DocumentContextExtracting {
    func extractContext(
        for document: ReaderDocument,
        question: String,
        scope: DocumentQueryScope,
        selection: DocumentSelection?,
        currentPageIndex: Int?,
        visiblePageIndexes: [Int]
    ) throws -> DocumentContext {
        try extractContext(
            for: document,
            question: question,
            scope: scope,
            selection: selection,
            currentPageIndex: currentPageIndex,
            visiblePageIndexes: visiblePageIndexes,
            isCancelled: { false },
            onProgress: { _ in }
        )
    }
}
