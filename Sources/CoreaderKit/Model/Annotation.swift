import Foundation

public enum AnnotationKind: String, Codable, Sendable {
    /// Marked passage, optionally with a note.
    case highlight
    /// Free-standing note attached to a place in the book.
    case note
    /// Image saved from the book: a region snip or a right-clicked figure.
    case image
}

public enum HighlightColor: String, Codable, Sendable, CaseIterable {
    case yellow, green, blue, pink, purple
}

/// One entry in a book's `notes.md`. The Markdown file is the only stored copy;
/// this struct is what the file parses to and is written from.
public struct Annotation: Codable, Sendable, Identifiable, Hashable {
    public var id: String
    public var kind: AnnotationKind
    /// The quoted passage (highlight) or a caption (image). Empty for a bare note.
    public var quote: String
    /// The reader's own words, Markdown.
    public var note: String
    public var color: HighlightColor
    public var locator: Locator
    /// Chapter or section title at the annotation, for grouping in the Markdown.
    public var chapter: String?
    /// File name inside the book's `assets/` folder, for images.
    public var asset: String?
    public var tags: [String]
    public var createdAt: Date

    public init(
        id: String = Annotation.newID(),
        kind: AnnotationKind,
        quote: String = "",
        note: String = "",
        color: HighlightColor = .yellow,
        locator: Locator,
        chapter: String? = nil,
        asset: String? = nil,
        tags: [String] = [],
        createdAt: Date = Date()
    ) {
        self.id = id
        self.kind = kind
        self.quote = quote
        self.note = note
        self.color = color
        self.locator = locator
        self.chapter = chapter
        self.asset = asset
        self.tags = tags
        self.createdAt = createdAt
    }

    /// Short, URL-safe id: annotations are referenced in deep links and Markdown.
    public static func newID() -> String {
        String(UUID().uuidString.lowercased().replacingOccurrences(of: "-", with: "").prefix(12))
    }
}

/// Deep links the app registers: `coreader://open?book=<id>&a=<annotationID>` and friends.
/// They appear in notes, agent answers and the CLI so any Markdown viewer can jump back
/// to the exact place in the book.
public enum DeepLink: Sendable, Equatable {
    case book(id: String)
    case annotation(bookID: String, annotationID: String)
    case location(bookID: String, locator: Locator)

    public static let scheme = "coreader"

    public var url: URL {
        var c = URLComponents()
        c.scheme = Self.scheme
        c.host = "open"
        switch self {
        case .book(let id):
            c.queryItems = [.init(name: "book", value: id)]
        case .annotation(let bookID, let annotationID):
            c.queryItems = [.init(name: "book", value: bookID), .init(name: "a", value: annotationID)]
        case .location(let bookID, let locator):
            var items = [URLQueryItem(name: "book", value: bookID)]
            if let cfi = locator.cfi { items.append(.init(name: "cfi", value: cfi)) }
            // Pages are one-based in links because people and agents read them.
            if let page = locator.page { items.append(.init(name: "page", value: String(page + 1))) }
            if locator.cfi == nil, locator.page == nil {
                items.append(.init(name: "at", value: String(format: "%.4f", locator.fraction)))
            }
            c.queryItems = items
        }
        return c.url!
    }

    public init?(url: URL) {
        guard url.scheme == Self.scheme,
              let c = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        let q = Dictionary((c.queryItems ?? []).compactMap { i in i.value.map { (i.name, $0) } }, uniquingKeysWith: { a, _ in a })
        guard let book = q["book"], !book.isEmpty else { return nil }
        if let a = q["a"] { self = .annotation(bookID: book, annotationID: a); return }
        if let cfi = q["cfi"] { self = .location(bookID: book, locator: Locator(cfi: cfi)); return }
        if let p = q["page"], let n = Int(p), n >= 1 { self = .location(bookID: book, locator: Locator(page: n - 1)); return }
        if let at = q["at"], let f = Double(at) { self = .location(bookID: book, locator: Locator(fraction: min(max(f, 0), 1))); return }
        self = .book(id: book)
    }
}
