protocol DocumentContextExtracting: Sendable {
    func extractContext(for document: ReaderDocument) throws -> DocumentContext
}
