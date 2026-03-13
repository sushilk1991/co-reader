struct DocumentChunk: Equatable, Sendable {
    let pageRange: ClosedRange<Int>
    let text: String
}
