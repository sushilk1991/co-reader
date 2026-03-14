protocol DocumentContextExtracting: Sendable {
    func extractContext(
        for document: ReaderDocument,
        question: String,
        scope: DocumentQueryScope,
        selection: DocumentSelection?,
        currentPageIndex: Int?,
        visiblePageIndexes: [Int]
    ) throws -> DocumentContext
}
