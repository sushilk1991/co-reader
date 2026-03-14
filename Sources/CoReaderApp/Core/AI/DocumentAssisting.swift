protocol DocumentAssisting: Sendable {
    func answer(
        question: String,
        for document: ReaderDocument,
        providerStatuses: [AIProviderStatus],
        scope: DocumentQueryScope,
        selection: DocumentSelection?,
        currentPageIndex: Int?,
        visiblePageIndexes: [Int],
        visualAsset: DocumentVisualAsset?
    ) async throws -> String
}
