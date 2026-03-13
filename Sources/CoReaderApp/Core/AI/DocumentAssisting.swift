protocol DocumentAssisting: Sendable {
    func answer(
        question: String,
        for document: ReaderDocument,
        providerStatuses: [AIProviderStatus],
        selection: DocumentSelection?,
        currentPageIndex: Int?,
        visiblePageIndexes: [Int]
    ) async throws -> String
}
