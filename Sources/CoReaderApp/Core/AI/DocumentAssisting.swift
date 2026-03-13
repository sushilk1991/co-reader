protocol DocumentAssisting: Sendable {
    func answer(
        question: String,
        for document: ReaderDocument,
        providerStatuses: [AIProviderStatus]
    ) async throws -> String
}
