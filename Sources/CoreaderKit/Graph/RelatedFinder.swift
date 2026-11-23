import Foundation

/// "This echoes something you highlighted in another book": the annotations closest in
/// meaning to a passage.
public struct RelatedFinder: Sendable {
    private let embedder: any TextEmbedding

    public init(embedder: any TextEmbedding = NLTextEmbedder()) {
        self.embedder = embedder
    }

    public struct Match: Sendable, Identifiable {
        public var id: String { annotation.id }
        public var book: Book
        public var annotation: Annotation
        /// Cosine similarity, -1...1; higher is closer.
        public var score: Double

        public init(book: Book, annotation: Annotation, score: Double) {
            self.book = book
            self.annotation = annotation
            self.score = score
        }
    }

    /// Best matches first. Empty when the text cannot be embedded. Pass the book being
    /// read as `excludingBookID` so a passage is not matched with its own neighbours.
    public func related(
        to text: String,
        among inputs: [GraphInput],
        excludingBookID: String?,
        limit: Int,
        minimumScore: Double
    ) -> [Match] {
        guard limit > 0, let query = embedder.vector(for: text).flatMap(VectorMath.normalized) else { return [] }
        let needle = text.split(whereSeparator: \.isWhitespace).joined(separator: " ").lowercased()

        var matches: [Match] = []
        for input in inputs where input.book.id != excludingBookID {
            for annotation in input.annotations {
                let candidate = annotation.graphText
                // The passage itself, already highlighted, is not an echo.
                if candidate.split(whereSeparator: \.isWhitespace).joined(separator: " ").lowercased() == needle { continue }
                guard let vector = embedder.vector(for: candidate).flatMap(VectorMath.normalized) else { continue }
                let score = VectorMath.dot(query, vector)
                if score >= minimumScore {
                    matches.append(Match(book: input.book, annotation: annotation, score: score))
                }
            }
        }
        matches.sort { ($0.score, $1.annotation.id) > ($1.score, $0.annotation.id) }
        return Array(matches.prefix(limit))
    }
}
