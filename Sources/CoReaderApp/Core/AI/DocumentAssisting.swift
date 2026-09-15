protocol DocumentAssisting: Sendable {
    func answer(
        question: String,
        for document: ReaderDocument,
        providerStatuses: [AIProviderStatus],
        scope: DocumentQueryScope,
        selection: DocumentSelection?,
        currentPageIndex: Int?,
        visiblePageIndexes: [Int],
        visualAsset: DocumentVisualAsset?,
        onProgress: @escaping @Sendable (DocumentAssistantProgress) -> Void
    ) async throws -> String
}
