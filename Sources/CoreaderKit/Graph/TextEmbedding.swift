import Foundation
import NaturalLanguage

/// Turns text into a vector whose direction carries its meaning. Injected so tests can
/// use a deterministic fake and so a better model can replace the built-in one.
public protocol TextEmbedding: Sendable {
    /// Nil when the text cannot be embedded (empty, unsupported language, model missing).
    func vector(for text: String) -> [Double]?
}

/// Apple's on-device English sentence embedding. No download, no network; returns nil on
/// systems where the model is unavailable.
public struct NLTextEmbedder: TextEmbedding {
    public init() {}

    public func vector(for text: String) -> [Double]? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return Model.shared.vector(for: trimmed)
    }

    /// Loading the model costs tens of milliseconds, so it is loaded once. `NLEmbedding`
    /// is not Sendable; the lock makes sharing it safe.
    private final class Model: @unchecked Sendable {
        static let shared = Model()
        private let lock = NSLock()
        private var loaded = false
        private var embedding: NLEmbedding?

        func vector(for text: String) -> [Double]? {
            lock.withLock {
                if !loaded {
                    embedding = NLEmbedding.sentenceEmbedding(for: .english)
                    loaded = true
                }
                return embedding?.vector(for: text)
            }
        }
    }
}

enum VectorMath {
    /// Unit-length copy, or nil for a zero or malformed vector.
    static func normalized(_ vector: [Double]) -> [Double]? {
        let length = vector.reduce(0) { $0 + $1 * $1 }.squareRoot()
        guard length > 0, length.isFinite else { return nil }
        return vector.map { $0 / length }
    }

    /// Cosine similarity for unit vectors of the same size.
    static func dot(_ a: [Double], _ b: [Double]) -> Double {
        guard a.count == b.count else { return 0 }
        var sum = 0.0
        for index in a.indices { sum += a[index] * b[index] }
        return sum
    }
}

extension Annotation {
    /// What an annotation says, for embedding and concept extraction: the passage and the
    /// reader's note together.
    var graphText: String {
        [quote, note].map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }.joined(separator: "\n")
    }
}
