import Foundation

/// File formats the reader opens. `article` is a saved web page (single HTML file).
public enum BookFormat: String, Codable, Sendable, CaseIterable {
    case epub, pdf, mobi, azw3, article

    public init?(fileExtension: String) {
        switch fileExtension.lowercased() {
        case "epub": self = .epub
        case "pdf": self = .pdf
        case "mobi", "prc": self = .mobi
        case "azw3", "azw", "kf8": self = .azw3
        case "html", "htm": self = .article
        default: return nil
        }
    }

    /// PDF renders with PDFKit; everything else renders in the web reader.
    public var isReflowable: Bool { self != .pdf }
}

/// What the item is, which decides shelf grouping and paper-only tools.
public enum BookKind: String, Codable, Sendable, CaseIterable {
    case book, paper, article
}

public enum ReadingStatus: String, Codable, Sendable, CaseIterable {
    case toRead, reading, read

    public var title: String {
        switch self {
        case .toRead: "To Read"
        case .reading: "Reading"
        case .read: "Read"
        }
    }
}

/// Where the reader is, or where an annotation points. One type for every format:
/// reflowable books use `cfi`; PDFs use `page` (zero-based) plus optional `rects`.
public struct Locator: Codable, Sendable, Hashable {
    /// EPUB CFI (`epubcfi(...)`), for reflowable formats.
    public var cfi: String?
    /// Zero-based page index, for PDFs.
    public var page: Int?
    /// PDF selection rectangles in page space, each `[x, y, width, height]`.
    public var rects: [[Double]]?
    /// Position in the whole book, 0...1. Always set; used for sorting and progress.
    public var fraction: Double
    /// Human label: "p. 42", or a chapter title.
    public var label: String?

    public init(cfi: String? = nil, page: Int? = nil, rects: [[Double]]? = nil, fraction: Double = 0, label: String? = nil) {
        self.cfi = cfi
        self.page = page
        self.rects = rects
        self.fraction = fraction
        self.label = label
    }
}

/// One item on the shelf. Persisted as `book.json` inside the book's folder; that file is
/// the single source of truth and syncs through iCloud Drive with the rest of the folder.
public struct Book: Codable, Sendable, Identifiable, Hashable {
    public var id: String
    public var title: String
    public var authors: [String]
    public var format: BookFormat
    public var kind: BookKind
    public var status: ReadingStatus
    /// 1...5 stars, nil when unrated.
    public var rating: Int?
    /// 0...1 through the whole book.
    public var progress: Double
    public var location: Locator?
    public var addedAt: Date
    public var lastOpenedAt: Date?
    public var finishedAt: Date?
    public var tags: [String]
    /// File name of the book inside its folder, e.g. `book.epub`.
    public var fileName: String
    /// File name of the cover image inside the folder, if any.
    public var coverFile: String?
    /// True when the cover was generated, not taken from the file.
    public var coverIsGenerated: Bool
    public var summary: String?
    public var publisher: String?
    public var year: Int?
    public var language: String?
    public var pageCount: Int?
    /// Where it came from: article URL, arXiv/DOI link.
    public var sourceURL: String?
    public var doi: String?
    public var arxivID: String?
    /// Seconds spent with this book open and in focus.
    public var secondsRead: Double

    public init(
        id: String = UUID().uuidString.lowercased(),
        title: String,
        authors: [String] = [],
        format: BookFormat,
        kind: BookKind = .book,
        status: ReadingStatus = .toRead,
        rating: Int? = nil,
        progress: Double = 0,
        location: Locator? = nil,
        addedAt: Date = Date(),
        lastOpenedAt: Date? = nil,
        finishedAt: Date? = nil,
        tags: [String] = [],
        fileName: String,
        coverFile: String? = nil,
        coverIsGenerated: Bool = false,
        summary: String? = nil,
        publisher: String? = nil,
        year: Int? = nil,
        language: String? = nil,
        pageCount: Int? = nil,
        sourceURL: String? = nil,
        doi: String? = nil,
        arxivID: String? = nil,
        secondsRead: Double = 0
    ) {
        self.id = id
        self.title = title
        self.authors = authors
        self.format = format
        self.kind = kind
        self.status = status
        self.rating = rating
        self.progress = progress
        self.location = location
        self.addedAt = addedAt
        self.lastOpenedAt = lastOpenedAt
        self.finishedAt = finishedAt
        self.tags = tags
        self.fileName = fileName
        self.coverFile = coverFile
        self.coverIsGenerated = coverIsGenerated
        self.summary = summary
        self.publisher = publisher
        self.year = year
        self.language = language
        self.pageCount = pageCount
        self.sourceURL = sourceURL
        self.doi = doi
        self.arxivID = arxivID
        self.secondsRead = secondsRead
    }

    public var authorLine: String { authors.joined(separator: ", ") }
}

/// A book together with the folder it lives in.
public struct BookEntry: Sendable, Identifiable, Hashable {
    public var book: Book
    /// `<library>/Books/<slug>/`
    public var folder: URL

    public init(book: Book, folder: URL) {
        self.book = book
        self.folder = folder
    }

    public var id: String { book.id }
    public var fileURL: URL { folder.appendingPathComponent(book.fileName) }
    public var coverURL: URL? { book.coverFile.map { folder.appendingPathComponent($0) } }
    public var notesURL: URL { folder.appendingPathComponent("notes.md") }
    public var assetsURL: URL { folder.appendingPathComponent("assets", isDirectory: true) }
    public var metadataURL: URL { folder.appendingPathComponent("book.json") }
}
