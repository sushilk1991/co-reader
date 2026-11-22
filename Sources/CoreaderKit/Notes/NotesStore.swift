import Foundation

/// Reads and writes each book's `notes.md`. Every change is read-modify-write of the
/// whole file, so text the user typed by hand since the last write is carried over.
public struct NotesStore: Sendable {
    public init() {}

    /// The parsed file, or an empty document for a book without notes yet.
    public func document(for entry: BookEntry) throws -> NotesDocument {
        guard FileManager.default.fileExists(atPath: entry.notesURL.path) else {
            return NotesDocument(bookID: entry.book.id, title: entry.book.title, authors: entry.book.authors)
        }
        return NotesDocument.parse(try String(contentsOf: entry.notesURL, encoding: .utf8))
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
        var document = try document(for: entry)
        if let index = document.annotations.firstIndex(where: { $0.id == annotation.id }) {
            document.annotations[index] = annotation
        } else {
            document.annotations.append(annotation)
        }
        try write(document, for: entry)
    }

    /// Removes the annotation. Its asset file, if any, stays in `assets/`: the user's
    /// own text may still point at it.
    public func remove(id: String, from entry: BookEntry) throws {
        guard FileManager.default.fileExists(atPath: entry.notesURL.path) else { return }
        var document = try document(for: entry)
        let ordered = NotesDocument.readingOrder(document.annotations)
        guard let position = ordered.firstIndex(where: { $0.id == id }) else { return }
        // Text the user wrote under this annotation moves up to whatever now precedes it.
        if let orphan = document.interleaved.removeValue(forKey: id) {
            if let previous = ordered[..<position].last(where: { $0.id != id }) {
                document.interleaved[previous.id] = document.interleaved[previous.id].map { $0 + "\n\n" + orphan } ?? orphan
            } else {
                document.preamble = document.preamble.isEmpty ? orphan : document.preamble + "\n\n" + orphan
            }
        }
        document.annotations.removeAll { $0.id == id }
        try write(document, for: entry)
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
