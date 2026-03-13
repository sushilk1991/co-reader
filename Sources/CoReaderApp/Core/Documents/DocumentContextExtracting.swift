protocol DocumentContextExtracting: Sendable {
    func extractContext(
        for document: ReaderDocument,
        question: String,
        selection: DocumentSelection?,
        currentPageIndex: Int?,
        visiblePageIndexes: [Int]
    ) throws -> DocumentContext
}
