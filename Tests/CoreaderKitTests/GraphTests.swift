import Foundation
import Testing
@testable import CoreaderKit

/// Bag-of-words over a tiny fixed vocabulary: texts sharing topic words point the same way.
private struct FakeEmbedder: TextEmbedding {
    static let vocabulary = ["entropy", "information", "memory", "habit", "attention", "market", "price", "sleep"]

    func vector(for text: String) -> [Double]? {
        let words = text.lowercased().split(whereSeparator: { !$0.isLetter }).map(String.init)
        let vector = Self.vocabulary.map { term in Double(words.filter { $0.hasPrefix(term) }.count) }
        return vector.contains { $0 > 0 } ? vector : nil
    }
}

private struct NoEmbedder: TextEmbedding {
    func vector(for text: String) -> [Double]? { nil }
}

private func book(_ id: String, _ title: String, tags: [String] = []) -> Book {
    Book(id: id, title: title, format: .epub, tags: tags, fileName: "\(id).epub")
}

private func note(_ id: String, _ quote: String, note: String = "", tags: [String] = []) -> Annotation {
    Annotation(id: id, kind: .highlight, quote: quote, note: note, locator: Locator(fraction: 0.5), tags: tags)
}

private let library: [GraphInput] = [
    GraphInput(book: book("info", "The Information", tags: ["Science"]), annotations: [
        note("i1", "Entropy measures the information we lack about a system.", tags: ["entropy"]),
        note("i2", "Memory is what lets a habit form at all.", note: "Compare [[Habit Loop]] and [[Entropy|disorder]]."),
        note("i3", "A sentence about gardening and nothing else."),
    ]),
    GraphInput(book: book("habits", "Atomic Habits"), annotations: [
        note("h1", "Every habit is stored in memory as a loop.", note: "See [[habit loop]]."),
        note("h2", "Markets set a price for attention.", tags: ["Economics"]),
    ]),
    GraphInput(book: book("thermo", "Order Out of Chaos"), annotations: [
        note("t1", "Information and entropy are two sides of one coin."),
    ]),
]

private func edges(_ graph: NoteGraph, _ kind: NoteGraph.Edge.Kind) -> [NoteGraph.Edge] {
    graph.edges.filter { $0.kind == kind }
}

@Test func graphHasBooksAnnotationsAndStructuralEdges() {
    let graph = GraphBuilder(embedder: FakeEmbedder()).build(from: library)
    #expect(graph.nodes.filter { $0.kind == .book }.map(\.id) == ["info", "habits", "thermo"])
    #expect(graph.nodes.filter { $0.kind == .annotation }.map(\.id) == ["i1", "i2", "i3", "h1", "h2", "t1"])
    let info = graph.nodes.first { $0.id == "info" }
    #expect(info?.label == "The Information")
    #expect(info?.weight == 3)
    let i1 = graph.nodes.first { $0.id == "i1" }
    #expect(i1?.bookID == "info")
    #expect(i1?.label == "Entropy measures the information we lack about a system.")

    let inBook = edges(graph, .inBook)
    #expect(inBook.count == 6)
    #expect(inBook.contains(.init(from: "h2", to: "habits", kind: .inBook)))
    // Every edge joins nodes that exist.
    let ids = Set(graph.nodes.map(\.id))
    #expect(graph.edges.allSatisfy { ids.contains($0.from) && ids.contains($0.to) })
    #expect(Set(graph.nodes.map(\.id)).count == graph.nodes.count)
}

@Test func graphConceptsComeFromTagsWikiLinksAndRecurringPhrases() {
    let graph = GraphBuilder(embedder: NoEmbedder()).build(from: library)
    let concepts = graph.nodes.filter { $0.kind == .concept }
    let byID = Dictionary(uniqueKeysWithValues: concepts.map { ($0.id, $0) })

    // Tag "entropy" on i1, wiki link [[Entropy|disorder]] on i2, and the word in t1 are one concept.
    let entropy = NoteGraph.conceptID("Entropy")
    #expect(entropy == "concept:entropy")
    #expect(byID[entropy] != nil)
    let entropyMentioners = Set(edges(graph, .mentions).filter { $0.to == entropy }.map(\.from))
    #expect(entropyMentioners.isSuperset(of: ["i1", "i2"]))
    #expect(byID[entropy]?.weight == Double(entropyMentioners.count))

    // Wiki links differing only in case meet; the reader's spelling is the label.
    let loop = NoteGraph.conceptID("Habit Loop")
    #expect(Set(edges(graph, .mentions).filter { $0.to == loop }.map(\.from)) == ["i2", "h1"])
    #expect(byID[loop]?.label.lowercased() == "habit loop")

    // Tags are kept even when used once, and book tags link the book.
    #expect(byID[NoteGraph.conceptID("Economics")]?.label == "Economics")
    #expect(edges(graph, .mentions).contains(.init(from: "info", to: NoteGraph.conceptID("Science"), kind: .mentions)))

    // "gardening" appears in one annotation only: not a concept.
    #expect(byID["concept:gardening"] == nil)
    // Heaviest concepts first.
    #expect(concepts.map(\.weight) == concepts.map(\.weight).sorted(by: >))
}

@Test func graphFindsRecurringNounPhrasesWithTheSystemTagger() {
    // Uses the real NLTagger: nouns that recur across annotations become concepts.
    let inputs = [
        GraphInput(book: book("a", "A"), annotations: [
            note("a1", "The neural network learns a representation of language."),
            note("a2", "Plain weather talk about rain."),
        ]),
        GraphInput(book: book("b", "B"), annotations: [
            note("b1", "A neural network is only as good as its training data."),
            note("b2", "Good training data matters more than the architecture."),
        ]),
    ]
    let graph = GraphBuilder(embedder: NoEmbedder()).build(from: inputs)
    let labels = Set(graph.nodes.filter { $0.kind == .concept }.map(\.label))
    #expect(labels.contains("neural network"))
    #expect(labels.contains("training data"))
    #expect(!labels.contains("network"))   // shadowed by the longer phrase from the same notes
    #expect(!labels.contains("rain"))
    let mentioners = Set(edges(graph, .mentions).filter { $0.to == "concept:neural network" }.map(\.from))
    #expect(mentioners == ["a1", "b1"])
}

@Test func graphLimitsConceptCount() {
    let graph = GraphBuilder(embedder: NoEmbedder()).build(from: library, maxConcepts: 2)
    #expect(graph.nodes.filter { $0.kind == .concept }.count == 2)
    #expect(GraphBuilder(embedder: NoEmbedder()).build(from: library, maxConcepts: 0).nodes.filter { $0.kind == .concept }.isEmpty)
}

@Test func graphSimilarEdgesOnlyCrossBooks() {
    let graph = GraphBuilder(embedder: FakeEmbedder()).build(from: library, similarityThreshold: 0.62)
    let similar = edges(graph, .similar)
    // i1 and t1 both speak of entropy and information; i2 and h1 of memory and habit.
    #expect(similar.contains { $0.from == "i1" && $0.to == "t1" && $0.strength > 0.99 })
    #expect(similar.contains { $0.from == "h1" && $0.to == "i2" && $0.strength > 0.9 })
    #expect(similar.count == 2)
    let bookOf = Dictionary(uniqueKeysWithValues: graph.nodes.filter { $0.kind == .annotation }.map { ($0.id, $0.bookID) })
    #expect(similar.allSatisfy { bookOf[$0.from] != bookOf[$0.to] })
    #expect(similar.allSatisfy { $0.from < $0.to })

    #expect(edges(GraphBuilder(embedder: FakeEmbedder()).build(from: library, similarityThreshold: 1.01), .similar).isEmpty)
    #expect(edges(GraphBuilder(embedder: NoEmbedder()).build(from: library), .similar).isEmpty)
}

@Test func graphCapsSimilarEdgesPerNode() {
    // One entropy note against eight in other books.
    var inputs = [GraphInput(book: book("hub", "Hub"), annotations: [note("hub1", "entropy")])]
    for index in 0..<8 {
        inputs.append(GraphInput(book: book("b\(index)", "B\(index)"), annotations: [note("n\(index)", "entropy again")]))
    }
    var builder = GraphBuilder(embedder: FakeEmbedder())
    builder.maxSimilarPerNode = 3
    let similar = edges(builder.build(from: inputs), .similar)
    var degree: [String: Int] = [:]
    for edge in similar { degree[edge.from, default: 0] += 1; degree[edge.to, default: 0] += 1 }
    #expect(degree.values.allSatisfy { $0 <= 3 })
    #expect(degree["hub1"] == 3)
}

@Test func graphBuildIsDeterministic() {
    let builder = GraphBuilder(embedder: FakeEmbedder())
    #expect(builder.build(from: library) == builder.build(from: library))
    #expect(builder.build(from: []) == NoteGraph())
}

@Test func graphWikiLinksAndKeys() {
    #expect(ConceptExtractor.wikiLinks(in: "a [[One]] b [[Two|shown]] c [[Three#Heading]] [[ ]] [[unclosed") == ["One", "Two", "Three"])
    #expect(ConceptExtractor.key("  Habit   Loop ") == "habit loop")
    #expect(ConceptExtractor.key("#Économie") == "economie")
    #expect(ConceptExtractor.key("deep_work") == "deep work")
    #expect(GraphBuilder.label(for: note("x", String(repeating: "word ", count: 40))).count <= 91)
    #expect(GraphBuilder.label(for: note("x", "", note: "only a note")) == "only a note")
}

// MARK: RelatedFinder

@Test func relatedFinderReturnsEchoesFromOtherBooks() {
    let finder = RelatedFinder(embedder: FakeEmbedder())
    let matches = finder.related(to: "Entropy is missing information.", among: library, excludingBookID: "info", limit: 5, minimumScore: 0.5)
    #expect(matches.map(\.id) == ["t1"])
    #expect(matches.first?.book.id == "thermo")
    #expect((matches.first?.score ?? 0) > 0.99)

    // Without the exclusion the current book's own notes can match too, best first.
    let all = finder.related(to: "Entropy is missing information.", among: library, excludingBookID: nil, limit: 5, minimumScore: 0.5)
    #expect(Set(all.map(\.id)) == ["i1", "t1"])
    #expect(all.map(\.score) == all.map(\.score).sorted(by: >))
    #expect(finder.related(to: "Entropy is missing information.", among: library, excludingBookID: nil, limit: 1, minimumScore: 0.5).count == 1)
}

@Test func relatedFinderHandlesNoMatchAndNoEmbedding() {
    let finder = RelatedFinder(embedder: FakeEmbedder())
    #expect(finder.related(to: "sleep", among: library, excludingBookID: nil, limit: 5, minimumScore: 0.5).isEmpty)
    #expect(finder.related(to: "words outside the vocabulary", among: library, excludingBookID: nil, limit: 5, minimumScore: 0).isEmpty)
    #expect(finder.related(to: "entropy", among: library, excludingBookID: nil, limit: 0, minimumScore: 0).isEmpty)
    #expect(RelatedFinder(embedder: NoEmbedder()).related(to: "entropy", among: library, excludingBookID: nil, limit: 5, minimumScore: 0).isEmpty)
    // The passage itself, already highlighted, is not its own echo.
    let same = finder.related(to: "  information and entropy are two sides of one coin. ", among: library,
                              excludingBookID: nil, limit: 5, minimumScore: 0.5)
    #expect(!same.map(\.id).contains("t1"))
}

@Test func vectorMathBasics() {
    #expect(VectorMath.normalized([3, 4]) == [0.6, 0.8])
    #expect(VectorMath.normalized([0, 0]) == nil)
    #expect(VectorMath.dot([1, 0], [0, 1]) == 0)
    #expect(VectorMath.dot([1, 0], [1]) == 0)
    // The real embedder never crashes; whether a model is installed is the system's business.
    _ = NLTextEmbedder().vector(for: "A sentence.")
    #expect(NLTextEmbedder().vector(for: "   ") == nil)
}

// MARK: GraphLayout

@Test func graphLayoutIsDeterministicAndNormalised() {
    let graph = GraphBuilder(embedder: FakeEmbedder()).build(from: library)
    let first = GraphLayout.layout(graph)
    let second = GraphLayout.layout(graph)
    #expect(first.count == graph.nodes.count)
    for node in graph.nodes {
        let a = first[node.id]!, b = second[node.id]!
        #expect(a.x == b.x && a.y == b.y)
        #expect((0...1).contains(a.x) && (0...1).contains(a.y))
        #expect(a.x.isFinite && a.y.isFinite)
    }
    // The longer side uses the whole range.
    let xs = first.values.map(\.x), ys = first.values.map(\.y)
    let span = max(xs.max()! - xs.min()!, ys.max()! - ys.min()!)
    #expect(abs(span - 1) < 1e-9)

    let other = GraphLayout.layout(graph, seed: 99)
    #expect(graph.nodes.contains { first[$0.id]!.x != other[$0.id]!.x })
}

@Test func graphLayoutPullsConnectedNodesTogether() {
    // Two triangles with no edge between them.
    let nodes = ["a1", "a2", "a3", "b1", "b2", "b3"].map { NoteGraph.Node(id: $0, kind: .annotation, label: $0) }
    let edgeList = [("a1", "a2"), ("a2", "a3"), ("a1", "a3"), ("b1", "b2"), ("b2", "b3"), ("b1", "b3")]
        .map { NoteGraph.Edge(from: $0.0, to: $0.1, kind: .similar, strength: 1) }
    let positions = GraphLayout.layout(NoteGraph(nodes: nodes, edges: edgeList))
    func distance(_ a: String, _ b: String) -> Double {
        let p = positions[a]!, q = positions[b]!
        return ((p.x - q.x) * (p.x - q.x) + (p.y - q.y) * (p.y - q.y)).squareRoot()
    }
    let within = [distance("a1", "a2"), distance("a2", "a3"), distance("b1", "b2"), distance("b2", "b3")].max()!
    let between = [distance("a1", "b1"), distance("a2", "b2"), distance("a3", "b3")].min()!
    #expect(within < between)
    // No two nodes on the same spot.
    for (i, a) in nodes.enumerated() { for b in nodes[(i + 1)...] { #expect(distance(a.id, b.id) > 0.01) } }
}

@Test func graphLayoutEdgeCases() {
    #expect(GraphLayout.layout(NoteGraph()).isEmpty)
    let one = GraphLayout.layout(NoteGraph(nodes: [.init(id: "solo", kind: .book, label: "Solo")]))
    #expect(one["solo"]?.x == 0.5 && one["solo"]?.y == 0.5)
    // Edges to unknown nodes and self-loops are ignored, not fatal.
    let odd = NoteGraph(nodes: [.init(id: "a", kind: .book, label: "A"), .init(id: "b", kind: .book, label: "B")],
                        edges: [.init(from: "a", to: "ghost", kind: .inBook), .init(from: "a", to: "a", kind: .inBook)])
    let positions = GraphLayout.layout(odd, iterations: 20)
    #expect(positions.count == 2)
    #expect(positions["a"]!.x != positions["b"]!.x || positions["a"]!.y != positions["b"]!.y)
}
