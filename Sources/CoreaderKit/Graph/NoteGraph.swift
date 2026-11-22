import Foundation
import NaturalLanguage

/// Books, their annotations and the ideas that connect them, ready to draw.
public struct NoteGraph: Sendable, Equatable {
    public struct Node: Sendable, Identifiable, Hashable {
        /// The book id or annotation id itself, so a tapped node opens directly; concepts
        /// use `NoteGraph.conceptID(_:)`.
        public var id: String
        public var kind: Kind
        public var label: String
        /// The owning book, for annotations (and the book itself for book nodes).
        public var bookID: String?
        /// Relative size: annotations in a book, mentions of a concept, 1 for an annotation.
        public var weight: Double

        public enum Kind: String, Sendable { case book, annotation, concept }

        public init(id: String, kind: Kind, label: String, bookID: String? = nil, weight: Double = 1) {
            self.id = id
            self.kind = kind
            self.label = label
            self.bookID = bookID
            self.weight = weight
        }
    }

    public struct Edge: Sendable, Hashable {
        public var from: String
        public var to: String
        public var kind: Kind
        /// 0...1. Cosine similarity for `similar`; 1 for the structural kinds.
        public var strength: Double

        public enum Kind: String, Sendable {
            /// annotation → its book
            case inBook
            /// annotation (or book, for book tags) → concept
            case mentions
            /// annotation ↔ annotation in another book that says something close
            case similar
        }

        public init(from: String, to: String, kind: Kind, strength: Double = 1) {
            self.from = from
            self.to = to
            self.kind = kind
            self.strength = strength
        }
    }

    public var nodes: [Node]
    public var edges: [Edge]

    public init(nodes: [Node] = [], edges: [Edge] = []) {
        self.nodes = nodes
        self.edges = edges
    }

    public static func conceptID(_ name: String) -> String {
        "concept:" + ConceptExtractor.key(name)
    }
}

public struct GraphInput: Sendable {
    public var book: Book
    public var annotations: [Annotation]

    public init(book: Book, annotations: [Annotation]) {
        self.book = book
        self.annotations = annotations
    }
}

public struct GraphBuilder: Sendable {
    private let embedder: any TextEmbedding
    /// Most `similar` edges one annotation may carry, so a common thought does not turn
    /// the picture into a hairball.
    public var maxSimilarPerNode = 4

    public init(embedder: any TextEmbedding = NLTextEmbedder()) {
        self.embedder = embedder
    }

    /// Builds the graph. Output order is deterministic: books, annotations, then concepts
    /// by weight.
    ///
    /// Concepts are the reader's tags and `[[wiki links]]` (always kept) plus noun phrases
    /// that recur in at least two annotations. Similarity is all pairs across books,
    /// which is fine for the few thousand highlights a library holds; call it off the
    /// main actor.
    public func build(from inputs: [GraphInput], maxConcepts: Int = 60, similarityThreshold: Double = 0.62) -> NoteGraph {
        var nodes: [NoteGraph.Node] = []
        var edges: [NoteGraph.Edge] = []
        var seen = Set<String>()
        var concepts: [String: Concept] = [:]
        var embedded: [(id: String, bookID: String, vector: [Double])] = []

        func mention(_ name: String, by nodeID: String, explicit: Bool, countsAsAnnotation: Bool) {
            let key = ConceptExtractor.key(name)
            guard !key.isEmpty else { return }
            var concept = concepts[key] ?? Concept(key: key, label: name)
            // What the reader typed beats what the tagger found, as the name shown.
            if explicit, !concept.explicit { concept.label = name }
            concept.explicit = concept.explicit || explicit
            concept.mentioners.insert(nodeID)
            if countsAsAnnotation { concept.annotations.insert(nodeID) }
            concepts[key] = concept
        }

        for input in inputs where seen.insert(input.book.id).inserted {
            let book = input.book
            nodes.append(.init(id: book.id, kind: .book, label: book.title, bookID: book.id,
                               weight: Double(max(input.annotations.count, 1))))
            for tag in book.tags { mention(tag, by: book.id, explicit: true, countsAsAnnotation: false) }
        }
        for input in inputs {
            for annotation in input.annotations where seen.insert(annotation.id).inserted {
                let text = annotation.graphText
                nodes.append(.init(id: annotation.id, kind: .annotation, label: Self.label(for: annotation),
                                   bookID: input.book.id, weight: 1))
                edges.append(.init(from: annotation.id, to: input.book.id, kind: .inBook))

                for tag in annotation.tags { mention(tag, by: annotation.id, explicit: true, countsAsAnnotation: true) }
                for link in ConceptExtractor.wikiLinks(in: annotation.note) {
                    mention(link, by: annotation.id, explicit: true, countsAsAnnotation: true)
                }
                for phrase in ConceptExtractor.nounPhrases(in: text) {
                    mention(phrase, by: annotation.id, explicit: false, countsAsAnnotation: true)
                }
                if let vector = embedder.vector(for: text).flatMap(VectorMath.normalized) {
                    embedded.append((annotation.id, input.book.id, vector))
                }
            }
        }

        // Concepts: everything explicit, then recurring phrases by how widely they recur.
        let ranked = concepts.values
            .filter { $0.explicit || $0.annotations.count >= 2 }
            .sorted { ($0.explicit ? 1 : 0, $0.score, $1.key) > ($1.explicit ? 1 : 0, $1.score, $0.key) }
        var kept: [Concept] = []
        for concept in ranked where kept.count < max(maxConcepts, 0) {
            // "network" adds nothing next to "neural network" when both come from the same notes.
            let shadowed = !concept.explicit && kept.contains { other in
                other.key != concept.key && other.words.count > concept.words.count
                    && concept.words.allSatisfy(other.words.contains) && concept.mentioners.isSubset(of: other.mentioners)
            }
            if !shadowed { kept.append(concept) }
        }
        kept.sort { ($0.mentioners.count, $1.label.lowercased()) > ($1.mentioners.count, $0.label.lowercased()) }
        for concept in kept {
            let id = "concept:" + concept.key
            nodes.append(.init(id: id, kind: .concept, label: concept.label, weight: Double(concept.mentioners.count)))
            for mentioner in concept.mentioners.sorted() {
                edges.append(.init(from: mentioner, to: id, kind: .mentions))
            }
        }

        // Similar passages in different books: strongest pairs first, each node capped.
        var pairs: [(a: Int, b: Int, score: Double)] = []
        for a in embedded.indices {
            for b in embedded.indices where b > a && embedded[a].bookID != embedded[b].bookID {
                let score = VectorMath.dot(embedded[a].vector, embedded[b].vector)
                if score >= similarityThreshold { pairs.append((a, b, score)) }
            }
        }
        pairs.sort { ($0.score, embedded[$1.a].id, embedded[$1.b].id) > ($1.score, embedded[$0.a].id, embedded[$0.b].id) }
        var degree: [Int: Int] = [:]
        for pair in pairs where degree[pair.a, default: 0] < maxSimilarPerNode && degree[pair.b, default: 0] < maxSimilarPerNode {
            degree[pair.a, default: 0] += 1
            degree[pair.b, default: 0] += 1
            let ids = [embedded[pair.a].id, embedded[pair.b].id].sorted()
            edges.append(.init(from: ids[0], to: ids[1], kind: .similar, strength: min(max(pair.score, 0), 1)))
        }

        return NoteGraph(nodes: nodes, edges: edges)
    }

    private struct Concept {
        var key: String
        var label: String
        var explicit = false
        /// Books and annotations that get an edge to this concept.
        var mentioners = Set<String>()
        /// Annotations only: recurrence is counted over these.
        var annotations = Set<String>()

        var words: [Substring] { key.split(separator: " ") }
        /// Phrases beat single words at the same count: they are more specific.
        var score: Double { Double(annotations.count) * (1 + 0.5 * Double(words.count - 1)) }
    }

    static func label(for annotation: Annotation, limit: Int = 90) -> String {
        let source = annotation.quote.isEmpty ? annotation.note : annotation.quote
        let line = source.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard line.count > limit else { return line }
        return line.prefix(limit).trimmingCharacters(in: .whitespaces) + "…"
    }
}

/// Finds what an annotation is about.
enum ConceptExtractor {
    /// Identity of a concept: case, accents and surrounding punctuation do not matter.
    static func key(_ name: String) -> String {
        name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .lowercased()
            .replacingOccurrences(of: "#", with: "")
            .split(whereSeparator: { $0.isWhitespace || $0 == "_" })
            .joined(separator: " ")
            .trimmingCharacters(in: .punctuationCharacters)
    }

    /// `[[Target]]` and `[[Target|shown text]]`, the Obsidian way.
    static func wikiLinks(in note: String) -> [String] {
        var links: [String] = []
        var rest = Substring(note)
        while let open = rest.range(of: "[["), let close = rest.range(of: "]]", range: open.upperBound..<rest.endIndex) {
            let inner = rest[open.upperBound..<close.lowerBound]
            let target = inner.split(separator: "|", maxSplits: 1).first.map(String.init) ?? ""
            let name = (target.split(separator: "#").first.map(String.init) ?? "").trimmingCharacters(in: .whitespaces)
            if !name.isEmpty, !name.contains("\n") { links.append(name) }
            rest = rest[close.upperBound...]
        }
        return links
    }

    /// Nouns too vague to be a topic.
    private static let vague: Set<String> = [
        "thing", "way", "people", "person", "time", "lot", "part", "kind", "sort", "one", "example", "fact", "case",
        "point", "something", "anything", "everything", "nothing", "someone", "other", "end", "day", "year", "bit",
        "place", "use", "number", "type", "form", "side", "world", "life", "man", "woman", "reason", "result",
    ]

    /// Noun phrases (optional adjectives, then nouns) and names, lowercased, the last word
    /// reduced to its lemma so "networks" and "network" meet. Each phrase once per text.
    static func nounPhrases(in text: String) -> [String] {
        guard !text.isEmpty else { return [] }
        let tagger = NLTagger(tagSchemes: [.nameTypeOrLexicalClass, .lemma])
        tagger.string = text
        var phrases: [String] = []
        var seen = Set<String>()
        var adjectives: [String] = []
        var nouns: [(word: String, lemma: String)] = []

        func add(_ words: [String]) {
            let phrase = words.suffix(3).joined(separator: " ")
            guard phrase.count >= 3, seen.insert(phrase).inserted else { return }
            phrases.append(phrase)
        }
        func flush() {
            defer { adjectives = []; nouns = [] }
            guard let head = nouns.last else { return }
            let nounWords = nouns.dropLast().map(\.word) + [head.lemma]
            if nounWords.count == 1 {
                guard head.lemma.count >= 4, !vague.contains(head.lemma) else { return }
            }
            add(nounWords)
            // With its adjectives too, when there is room: "deep neural network".
            if !adjectives.isEmpty, nounWords.count < 3, !vague.contains(head.lemma) {
                add(adjectives.suffix(3 - nounWords.count) + nounWords)
            }
        }

        let options: NLTagger.Options = [.omitWhitespace, .joinNames]
        tagger.enumerateTags(in: text.startIndex..<text.endIndex, unit: .word, scheme: .nameTypeOrLexicalClass, options: options) { tag, range in
            let word = String(text[range])
            switch tag {
            case .personalName?, .placeName?, .organizationName?:
                flush()
                if word.count >= 3, seen.insert(word.lowercased()).inserted { phrases.append(word.lowercased()) }
            case .noun?:
                let lower = word.lowercased()
                let lemma = tagger.tag(at: range.lowerBound, unit: .word, scheme: .lemma).0?.rawValue.lowercased() ?? lower
                if lower.allSatisfy({ $0.isLetter || $0 == "-" }) {
                    nouns.append((lower, lemma.isEmpty ? lower : lemma))
                } else {
                    flush()
                }
            case .adjective?:
                // An adjective after nouns starts a new phrase.
                if !nouns.isEmpty { flush() }
                adjectives.append(word.lowercased())
            default:
                flush()
            }
            return true
        }
        flush()
        return phrases
    }
}
