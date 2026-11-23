import Foundation

/// What the importer knows about a file beyond its bytes. Everything is optional:
/// whatever is missing falls back to the file name or the model's defaults.
public struct ImportMetadata: Sendable, Equatable {
    public var title: String?
    public var authors: [String]?
    public var kind: BookKind?
    public var summary: String?
    public var publisher: String?
    public var year: Int?
    public var language: String?
    public var pageCount: Int?
    public var sourceURL: String?
    public var doi: String?
    public var arxivID: String?

    public init(
        title: String? = nil,
        authors: [String]? = nil,
        kind: BookKind? = nil,
        summary: String? = nil,
        publisher: String? = nil,
        year: Int? = nil,
        language: String? = nil,
        pageCount: Int? = nil,
        sourceURL: String? = nil,
        doi: String? = nil,
        arxivID: String? = nil
    ) {
        self.title = title
        self.authors = authors
        self.kind = kind
        self.summary = summary
        self.publisher = publisher
        self.year = year
        self.language = language
        self.pageCount = pageCount
        self.sourceURL = sourceURL
        self.doi = doi
        self.arxivID = arxivID
    }
}

public enum LibraryError: Error, LocalizedError, Equatable {
    case fileNotFound(String)
    case unsupportedFormat(String)
    case bookNotFound(String)

    public var errorDescription: String? {
        switch self {
        case .fileNotFound(let path):
            "No file at \(path)."
        case .unsupportedFormat(let ext):
            "Coreader cannot open \(ext.isEmpty ? "files without an extension" : ".\(ext) files"). Supported: epub, pdf, mobi, azw3, html."
        case .bookNotFound(let id):
            "No book with id \(id) in the library."
        }
    }
}

/// The library folder: one sub-folder per book under `Books/`, each holding `book.json`,
/// the book file, `notes.md` and friends. See `AGENTS.md` for the contract.
public struct LibraryStore: Sendable {
    public let root: URL

    public init(root: URL) {
        self.root = root
    }

    public var booksRoot: URL { root.appendingPathComponent("Books", isDirectory: true) }
    public var readmeURL: URL { root.appendingPathComponent("README.md") }

    /// Outcome of an import: `isDuplicate` is true when the file was already in the
    /// library and `entry` is the book that was there.
    public struct ImportResult: Sendable {
        public var entry: BookEntry
        public var isDuplicate: Bool
    }

    public func prepare() throws {
        try FileManager.default.createDirectory(at: booksRoot, withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: readmeURL.path) {
            // Unreadable (evicted by iCloud, not UTF-8) counts as not ours: leave it.
            guard let existing = try? String(contentsOf: readmeURL, encoding: .utf8),
                  LibraryReadme.needsWrite(existing: existing) else { return }
        }
        try AtomicFile.write(LibraryReadme.text, to: readmeURL)
    }

    /// Asks iCloud for the `book.json` of every book folder whose metadata is not on
    /// this Mac yet, and returns how many were asked for. Such books are missing from
    /// `allBooks()` until the download lands, so the caller should list again shortly.
    public func requestEvictedMetadata() -> Int {
        let fm = FileManager.default
        guard let folders = try? fm.contentsOfDirectory(at: booksRoot, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { return 0 }
        var asked = 0
        for folder in folders {
            let metadata = folder.appendingPathComponent("book.json")
            let placeholder = folder.appendingPathComponent(".book.json.icloud")
            let present = fm.fileExists(atPath: metadata.path)
            if present, (try? Data(contentsOf: metadata)) != nil { continue }
            guard present || fm.fileExists(atPath: placeholder.path) else { continue }
            if (try? fm.startDownloadingUbiquitousItem(at: metadata)) != nil { asked += 1 }
        }
        return asked
    }

    /// Every readable book, sorted by title. A folder whose `book.json` is missing or
    /// damaged (half-synced, hand-edited) is skipped so one bad folder never hides the shelf.
    public func allBooks() throws -> [BookEntry] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: booksRoot.path) else { return [] }
        let folders = try fm.contentsOfDirectory(
            at: booksRoot, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])
        let decoder = LibraryJSON.decoder()
        var entries: [BookEntry] = []
        for found in folders {
            // Rebuilt from `root` so a scanned entry and a freshly imported one have the
            // same folder URL (the enumerator resolves symlinks such as /var → /private/var).
            let folder = booksRoot.appendingPathComponent(found.lastPathComponent, isDirectory: true)
            guard (try? found.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true,
                  let data = try? Data(contentsOf: folder.appendingPathComponent("book.json")),
                  let book = try? decoder.decode(Book.self, from: data) else { continue }
            entries.append(BookEntry(book: book, folder: folder))
        }
        return entries.sorted {
            let order = $0.book.title.localizedCaseInsensitiveCompare($1.book.title)
            return order == .orderedSame ? $0.folder.lastPathComponent < $1.folder.lastPathComponent : order == .orderedAscending
        }
    }

    public func entry(id: String) throws -> BookEntry? {
        try allBooks().first { $0.book.id == id }
    }

    public func importFile(at source: URL, metadata: ImportMetadata) throws -> BookEntry {
        try importFileReportingDuplicate(at: source, metadata: metadata).entry
    }

    /// `importFile`, but also says whether the file was already in the library.
    public func importFileReportingDuplicate(at source: URL, metadata: ImportMetadata = ImportMetadata()) throws -> ImportResult {
        let fm = FileManager.default
        var isDirectory: ObjCBool = false
        guard fm.fileExists(atPath: source.path, isDirectory: &isDirectory), !isDirectory.boolValue else {
            throw LibraryError.fileNotFound(source.path)
        }
        let ext = source.pathExtension.lowercased()
        guard let format = BookFormat(fileExtension: ext) else { throw LibraryError.unsupportedFormat(ext) }

        try prepare()
        let hash = try SHA256.hex(ofFileAt: source)
        if let existing = try existingBook(withHash: hash, sizeOf: source) {
            return ImportResult(entry: existing, isDuplicate: true)
        }

        let fileTitle = source.deletingPathExtension().lastPathComponent
        let title = metadata.title.flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty } ?? fileTitle
        let slug = uniqueSlug(Slug.make(title, fallback: Slug.make(fileTitle, fallback: "book")))
        let fileName = "\(slug).\(ext)"
        let book = Book(
            title: title,
            authors: metadata.authors ?? [],
            format: format,
            kind: metadata.kind ?? (format == .article ? .article : .book),
            fileName: fileName,
            summary: metadata.summary,
            publisher: metadata.publisher,
            year: metadata.year,
            language: metadata.language,
            pageCount: metadata.pageCount,
            sourceURL: metadata.sourceURL,
            doi: metadata.doi,
            arxivID: metadata.arxivID,
            contentHash: hash
        )

        // Build the folder under a hidden name and rename it into place, so neither a
        // library scan nor iCloud ever sees a book folder without its book.json.
        let staging = booksRoot.appendingPathComponent(".import-\(UUID().uuidString)", isDirectory: true)
        let folder = booksRoot.appendingPathComponent(slug, isDirectory: true)
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        do {
            try fm.copyItem(at: source, to: staging.appendingPathComponent(fileName))
            try save(book, in: staging)
            try fm.moveItem(at: staging, to: folder)
        } catch {
            try? fm.removeItem(at: staging)
            throw error
        }
        return ImportResult(entry: BookEntry(book: book, folder: folder), isDuplicate: false)
    }

    public func save(_ book: Book, in folder: URL) throws {
        let data = try LibraryJSON.encoder().encode(book)
        try AtomicFile.write(data, to: folder.appendingPathComponent("book.json"))
    }

    public func setCover(_ data: Data, fileExtension: String, generated: Bool, forBookID id: String) throws -> BookEntry {
        guard var entry = try entry(id: id) else { throw LibraryError.bookNotFound(id) }
        var ext = fileExtension.lowercased().filter { $0.isASCII && ($0.isLetter || $0.isNumber) }
        if ext == "jpeg" { ext = "jpg" }
        if ext.isEmpty { ext = "jpg" }
        let fileName = "cover.\(ext)"
        try AtomicFile.write(data, to: entry.folder.appendingPathComponent(fileName))
        if let old = entry.book.coverFile, old != fileName {
            try? FileManager.default.removeItem(at: entry.folder.appendingPathComponent(old))
        }
        entry.book.coverFile = fileName
        entry.book.coverIsGenerated = generated
        try save(entry.book, in: entry.folder)
        return entry
    }

    /// Writes a cover image into a book folder and returns its file name, removing the
    /// previous cover file when its name differs. Does not touch `book.json`: callers
    /// that hold newer metadata in memory record the new name themselves.
    public func writeCoverFile(_ data: Data, fileExtension: String, in folder: URL, replacing old: String?) throws -> String {
        var ext = fileExtension.lowercased().filter { $0.isASCII && ($0.isLetter || $0.isNumber) }
        if ext == "jpeg" { ext = "jpg" }
        if ext.isEmpty { ext = "jpg" }
        let fileName = "cover.\(ext)"
        try AtomicFile.write(data, to: folder.appendingPathComponent(fileName))
        if let old, old != fileName { try? FileManager.default.removeItem(at: folder.appendingPathComponent(old)) }
        return fileName
    }

    public func delete(id: String) throws {
        try delete(id: id, toTrash: true)
    }

    /// `toTrash: false` removes the folder outright; tests use it so they never put
    /// anything in the real Trash.
    func delete(id: String, toTrash: Bool) throws {
        guard let entry = try entry(id: id) else { throw LibraryError.bookNotFound(id) }
        let fm = FileManager.default
        // No fallback to deleting outright: the folder holds the only copy of the notes,
        // so if the Trash refuses it, the book stays and the caller is told.
        if toTrash {
            try fm.trashItem(at: entry.folder, resultingItemURL: nil)
        } else {
            try fm.removeItem(at: entry.folder)
        }
    }

    // MARK: - Helpers

    private func existingBook(withHash hash: String, sizeOf source: URL) throws -> BookEntry? {
        let size = fileSize(source)
        for var entry in try allBooks() {
            if entry.book.contentHash == hash { return entry }
            // Books written before `contentHash` existed: hash them only when the size
            // matches, and remember the answer.
            guard entry.book.contentHash == nil, size != nil, fileSize(entry.fileURL) == size,
                  let theirs = try? SHA256.hex(ofFileAt: entry.fileURL) else { continue }
            entry.book.contentHash = theirs
            try? save(entry.book, in: entry.folder)
            if theirs == hash { return entry }
        }
        return nil
    }

    private func fileSize(_ url: URL) -> Int? {
        (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize
    }

    private func uniqueSlug(_ base: String) -> String {
        let fm = FileManager.default
        var slug = base
        var n = 2
        while fm.fileExists(atPath: booksRoot.appendingPathComponent(slug).path) {
            slug = "\(base)-\(n)"
            n += 1
        }
        return slug
    }
}

extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
