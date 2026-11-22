import Foundation
#if canImport(PDFKit)
import PDFKit
#endif

/// The plain text of a book, split into sections, cached under
/// `<caches>/text/<bookID>/`. It is derived data: agents and the CLI read it, and it can
/// be deleted at any time and extracted again.
public struct BookTextStore: Sendable {
    public struct Section: Codable, Sendable, Equatable {
        /// Position the producer assigned (zero-based page for PDFs, spine index for EPUBs).
        public var index: Int
        public var title: String
        public var locator: Locator
        public var text: String

        public init(index: Int, title: String, locator: Locator, text: String) {
            self.index = index
            self.title = title
            self.locator = locator
            self.text = text
        }
    }

    public enum TextError: Error, LocalizedError, Equatable {
        case noText(String)
        case unreadablePDF(String)
        case pdfUnavailable

        public var errorDescription: String? {
            switch self {
            case .noText(let id): "No extracted text for book \(id)."
            case .unreadablePDF(let path): "Could not read the PDF at \(path) (damaged or password-protected)."
            case .pdfUnavailable: "PDF text extraction is not available on this platform."
            }
        }
    }

    public let cachesRoot: URL

    public init(cachesRoot: URL = LibraryConfig.cachesRoot) {
        self.cachesRoot = cachesRoot
    }

    public func folder(for bookID: String) -> URL {
        // Ids are UUIDs, but a hand-edited book.json must not be able to point outside the cache.
        let safe = bookID.map { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" ? $0 : "_" }
        return cachesRoot.appendingPathComponent("text", isDirectory: true)
            .appendingPathComponent(safe.isEmpty ? "_" : String(safe), isDirectory: true)
    }

    public func hasText(for bookID: String) -> Bool {
        FileManager.default.fileExists(atPath: indexURL(for: bookID).path)
    }

    /// File names of the saved sections, in order.
    public func sectionFiles(for bookID: String) throws -> [URL] {
        try index(for: bookID).sections.map { folder(for: bookID).appendingPathComponent($0.file) }
    }

    /// Writes one `NNN-<slug>.md` per section plus `index.json`, replacing whatever was
    /// cached before. Each file starts with `# <title>`, then a link that opens that
    /// place in the app, then the text exactly as given.
    public func save(_ sections: [Section], for book: Book) throws {
        let fm = FileManager.default
        let folder = folder(for: book.id)
        let parent = folder.deletingLastPathComponent()
        try fm.createDirectory(at: parent, withIntermediateDirectories: true)
        // Build beside the final folder and swap, so a reader never sees half a book.
        let staging = parent.appendingPathComponent(".\(folder.lastPathComponent)-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        do {
            let width = max(3, String(sections.count).count)
            var entries: [Index.Entry] = []
            for (n, section) in sections.enumerated() {
                let number = String(repeating: "0", count: max(0, width - String(n + 1).count)) + String(n + 1)
                let file = "\(number)-\(Slug.make(section.title, fallback: "section", maxLength: 40)).md"
                let link = DeepLink.location(bookID: book.id, locator: section.locator).url.absoluteString
                let header = "# \(NotesText.singleLine(section.title))\n\n[Open in Coreader](\(link))\n\n"
                try AtomicFile.write(header + section.text, to: staging.appendingPathComponent(file))
                entries.append(Index.Entry(
                    file: file, index: section.index, title: section.title,
                    locator: section.locator, characters: section.text.count))
            }
            let index = Index(bookID: book.id, title: book.title, sections: entries)
            try AtomicFile.write(try LibraryJSON.encoder().encode(index), to: staging.appendingPathComponent("index.json"))
            if fm.fileExists(atPath: folder.path) {
                _ = try fm.replaceItemAt(folder, withItemAt: staging)
            } else {
                try fm.moveItem(at: staging, to: folder)
            }
        } catch {
            try? fm.removeItem(at: staging)
            throw error
        }
    }

    public func load(for bookID: String) throws -> [Section] {
        let folder = folder(for: bookID)
        return try index(for: bookID).sections.map { entry in
            let content = try String(contentsOf: folder.appendingPathComponent(entry.file), encoding: .utf8)
            // Header is four lines: title, blank, link, blank. The rest is the text, verbatim.
            let parts = content.split(separator: "\n", maxSplits: 4, omittingEmptySubsequences: false)
            return Section(
                index: entry.index, title: entry.title, locator: entry.locator,
                text: parts.count == 5 ? String(parts[4]) : "")
        }
    }

    /// One section per page: title "Page N", `locator.page` zero-based.
    /// Walks the whole document, so call it off the main thread.
    public func extractPDF(at url: URL, book: Book) throws -> [Section] {
        #if canImport(PDFKit)
        guard let document = PDFDocument(url: url), !document.isLocked else {
            throw TextError.unreadablePDF(url.path)
        }
        let count = document.pageCount
        return (0..<count).map { page in
            Section(
                index: page,
                title: "Page \(page + 1)",
                locator: Locator(page: page, fraction: Double(page) / Double(count), label: "p. \(page + 1)"),
                text: document.page(at: page)?.string ?? "")
        }
        #else
        throw TextError.pdfUnavailable
        #endif
    }

    // MARK: - Index

    struct Index: Codable {
        struct Entry: Codable {
            var file: String
            var index: Int
            var title: String
            var locator: Locator
            var characters: Int
        }
        var bookID: String
        var title: String
        var sections: [Entry]
    }

    private func indexURL(for bookID: String) -> URL {
        folder(for: bookID).appendingPathComponent("index.json")
    }

    func index(for bookID: String) throws -> Index {
        guard let data = try? Data(contentsOf: indexURL(for: bookID)) else { throw TextError.noText(bookID) }
        return try LibraryJSON.decoder().decode(Index.self, from: data)
    }
}
