import Foundation

/// Reads and writes each book's `notes.md`. Every change is read-modify-write of the
/// whole file, so text the user typed by hand since the last write is carried over.
public struct NotesStore: Sendable {
    public init() {}

    /// `notes.md` exists in iCloud but its contents are not on this Mac.
    public struct NotesNotDownloaded: LocalizedError {
        public var errorDescription: String? { "This book's notes are still downloading from iCloud. Try again in a moment." }
    }

    /// The parsed file, or an empty document for a book without notes yet.
    public func document(for entry: BookEntry) throws -> NotesDocument {
        guard FileManager.default.fileExists(atPath: entry.notesURL.path) else {
            // Older iCloud leaves ".notes.md.icloud" in place of an evicted file. Treating
            // that as "no notes yet" would write a new file over the real one.
            let placeholder = entry.notesURL.deletingLastPathComponent().appendingPathComponent(".notes.md.icloud")
            if FileManager.default.fileExists(atPath: placeholder.path) {
                try? FileManager.default.startDownloadingUbiquitousItem(at: entry.notesURL)
                throw NotesNotDownloaded()
            }
            return NotesDocument(bookID: entry.book.id, title: entry.book.title, authors: entry.book.authors)
        }
        return NotesDocument.parse(try String(contentsOf: entry.notesURL, encoding: .utf8))
    }

    private static func fingerprint(_ url: URL) -> [String] {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path) else { return ["absent"] }
        let modified = (attributes[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        return ["\(modified)", "\(attributes[.size] ?? 0)", "\(attributes[.systemFileNumber] ?? 0)"]
    }

    /// Read, change, write. If another app (Obsidian, an agent, iCloud) replaced the file
    /// between the read and the write, the change is applied again to the newer file
    /// instead of writing the older one back over it.
    private func mutate<T>(_ entry: BookEntry, _ change: (inout NotesDocument) throws -> T?) throws -> T? {
        var attempt = 0
        while true {
            let before = Self.fingerprint(entry.notesURL)
            var document = try document(for: entry)
            guard let result = try change(&document) else { return nil }
            if Self.fingerprint(entry.notesURL) != before, attempt < 3 {
                attempt += 1
                continue
            }
            try write(document, for: entry)
            return result
        }
    }

    /// Writes the document, stamping it with the book's current title, authors and id
    /// (`book.json` is the authority for those) and the time of the write.
    public func write(_ document: NotesDocument, for entry: BookEntry, now: Date = Date()) throws {
        var document = document
        document.bookID = entry.book.id
        document.title = entry.book.title
        document.authors = entry.book.authors
        document.updated = now
        try AtomicFile.write(document.markdown(), to: entry.notesURL)
    }

    /// Annotations in reading order; `[]` when `notes.md` is absent.
    public func load(_ entry: BookEntry) throws -> [Annotation] {
        NotesDocument.readingOrder(try document(for: entry).annotations)
    }

    public func upsert(_ annotation: Annotation, in entry: BookEntry) throws {
        _ = try mutate(entry) { document -> Bool? in
            if let index = document.annotations.firstIndex(where: { $0.id == annotation.id }) {
                document.annotations[index] = annotation
            } else {
                document.annotations.append(annotation)
            }
            return true
        }
    }

    /// Applies a change to the annotation as it is in the file right now, not to a copy
    /// loaded earlier: text edited in another app since the book was opened is kept.
    /// Returns the annotation as written, or nil when it is no longer in the file.
    @discardableResult
    public func update(id: String, in entry: BookEntry, _ change: (inout Annotation) -> Void) throws -> Annotation? {
        try mutate(entry) { document -> Annotation? in
            guard let index = document.annotations.firstIndex(where: { $0.id == id }) else { return nil }
            change(&document.annotations[index])
            return document.annotations[index]
        }
    }

    /// Removes the annotation. Its asset file, if any, stays in `assets/`: the user's
    /// own text may still point at it.
    public func remove(id: String, from entry: BookEntry) throws {
        _ = try mutate(entry) { document -> Bool? in
        let ordered = NotesDocument.readingOrder(document.annotations)
        guard let position = ordered.firstIndex(where: { $0.id == id }) else { return nil }
        // Text the user wrote under this annotation moves up to whatever now precedes it.
        if let orphan = document.interleaved.removeValue(forKey: id) {
            if let previous = ordered[..<position].last(where: { $0.id != id }) {
                document.interleaved[previous.id] = document.interleaved[previous.id].map { $0 + "\n\n" + orphan } ?? orphan
            } else {
                document.preamble = document.preamble.isEmpty ? orphan : document.preamble + "\n\n" + orphan
            }
        }
        document.annotations.removeAll { $0.id == id }
        return true
        }
    }

    /// Saves an image into the book's `assets/` folder under a unique, readable name and
    /// returns that file name (what `Annotation.asset` should hold).
    public func saveAsset(_ data: Data, suggestedName: String, fileExtension: String, in entry: BookEntry) throws -> String {
        let fm = FileManager.default
        try fm.createDirectory(at: entry.assetsURL, withIntermediateDirectories: true)
        let base = Slug.make(suggestedName, fallback: "image", maxLength: 48)
        let ext = fileExtension.lowercased().filter { $0.isASCII && ($0.isLetter || $0.isNumber) }.nonEmpty ?? "png"
        var name = "\(base).\(ext)"
        var n = 2
        while fm.fileExists(atPath: entry.assetsURL.appendingPathComponent(name).path) {
            name = "\(base)-\(n).\(ext)"
            n += 1
        }
        try AtomicFile.write(data, to: entry.assetsURL.appendingPathComponent(name))
        return name
    }

    /// Every annotation in the library: books in shelf order, annotations in reading
    /// order. A book whose notes cannot be read is skipped.
    public func all(in library: LibraryStore) throws -> [(entry: BookEntry, annotation: Annotation)] {
        var result: [(entry: BookEntry, annotation: Annotation)] = []
        for entry in try library.allBooks() {
            guard let annotations = try? load(entry) else { continue }
            result += annotations.map { (entry, $0) }
        }
        return result
    }

    /// Annotations whose quote, note or tags contain every word of the query, ignoring
    /// case, accents and width. An empty query matches nothing.
    public func search(_ query: String, in library: LibraryStore) throws -> [(entry: BookEntry, annotation: Annotation)] {
        let terms = Self.fold(query).split(whereSeparator: \.isWhitespace)
        guard !terms.isEmpty else { return [] }
        return try all(in: library).filter { hit in
            let haystack = Self.fold(([hit.annotation.quote, hit.annotation.note] + hit.annotation.tags).joined(separator: "\n"))
            return terms.allSatisfy { haystack.contains($0) }
        }
    }

    static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
    }
}
