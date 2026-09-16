protocol DocumentContextExtracting: Sendable {
    /// Implementations run blocking reads through `BlockingWork` and await subprocesses.
    /// Poll `isCancelled` between pages and report each finished page to `onProgress`.
    func extractContext(
        for document: ReaderDocument,
        question: String,
        scope: DocumentQueryScope,
        selection: DocumentSelection?,
        currentPageIndex: Int?,
        visiblePageIndexes: [Int],
        isCancelled: @escaping @Sendable () -> Bool,
        onProgress: @escaping @Sendable (PageScanProgress) -> Void
    ) async throws -> DocumentContext
}

extension DocumentContextExtracting {
    func extractContext(
        for document: ReaderDocument,
        question: String,
        scope: DocumentQueryScope,
        selection: DocumentSelection?,
        currentPageIndex: Int?,
        visiblePageIndexes: [Int]
    ) async throws -> DocumentContext {
        try await extractContext(
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
