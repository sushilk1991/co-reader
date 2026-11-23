import Foundation

/// One annotation together with the book it belongs to: a row in the notebook that
/// lists every note in the library.
public struct LibraryNote: Sendable, Identifiable, Hashable {
    public var entry: BookEntry
    public var annotation: Annotation

    public init(entry: BookEntry, annotation: Annotation) {
        self.entry = entry
        self.annotation = annotation
    }

    /// Annotation ids are unique within a book, not across the library.
    public var id: String { entry.id + "/" + annotation.id }
}

/// What the notebook is showing: which book, which kind, which colour, the search text
/// and the order.
public struct NotebookQuery: Sendable, Equatable {
    public enum Kind: String, Sendable, CaseIterable {
        /// Marked passages.
        case highlights
        /// Anything the reader wrote words on: bare notes and highlights with a note.
        case notes
        /// Saved figures and snips.
        case images
    }

    public enum Sort: String, Sendable, CaseIterable {
        /// Grouped by book (most recently annotated first), in reading order within it.
        case book
        case newest
        case oldest
    }

    public var bookID: String?
    public var kind: Kind?
    public var color: HighlightColor?
    public var text = ""
    public var sort = Sort.book

    public init() {}

    /// True when anything narrows the list (the order does not).
    public var isFiltering: Bool {
        bookID != nil || kind != nil || color != nil || !text.trimmingCharacters(in: .whitespaces).isEmpty
    }

    public func matches(_ note: LibraryNote) -> Bool {
        let a = note.annotation
        if let bookID, note.entry.id != bookID { return false }
        switch kind {
        case .highlights?: if a.kind != .highlight { return false }
        case .notes?: if a.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return false }
        case .images?: if a.kind != .image { return false }
        case nil: break
        }
        // Colour belongs to marked text; an image or a bare note has none to show.
        if let color, a.kind != .highlight || a.color != color { return false }
        let terms = NotesStore.fold(text).split(whereSeparator: \.isWhitespace)
        guard !terms.isEmpty else { return true }
        let haystack = NotesStore.fold(([a.quote, a.note, a.chapter ?? "", note.entry.book.title, note.entry.book.authorLine] + a.tags).joined(separator: "\n"))
        return terms.allSatisfy { haystack.contains($0) }
    }

    /// The matching notes in display order. `notes` is expected in reading order within
    /// each book, as `NotesStore.all` returns it.
    public func apply(to notes: [LibraryNote]) -> [LibraryNote] {
        let hits = notes.filter(matches)
        switch sort {
        case .newest: return Self.stable(hits) { $0.annotation.createdAt > $1.annotation.createdAt }
        case .oldest: return Self.stable(hits) { $0.annotation.createdAt < $1.annotation.createdAt }
        case .book:
            // A book's place is decided by all of its notes, not just the ones showing,
            // so the groups do not jump around while typing a search.
            var latest: [String: Date] = [:]
            for note in notes { latest[note.entry.id] = max(latest[note.entry.id] ?? .distantPast, note.annotation.createdAt) }
            return Self.stable(hits) { l, r in
                guard l.entry.id != r.entry.id else { return false }
                let a = latest[l.entry.id] ?? .distantPast, b = latest[r.entry.id] ?? .distantPast
                return a != b ? a > b : l.entry.id < r.entry.id
            }
        }
    }

    private static func stable(_ notes: [LibraryNote], _ before: (LibraryNote, LibraryNote) -> Bool) -> [LibraryNote] {
        notes.enumerated().sorted { l, r in
            if before(l.element, r.element) { return true }
            if before(r.element, l.element) { return false }
            return l.offset < r.offset
        }.map(\.element)
    }

    /// Books that have notes, most recently annotated first, with how many each has.
    public static func books(in notes: [LibraryNote]) -> [(entry: BookEntry, count: Int)] {
        var counts: [String: Int] = [:], latest: [String: Date] = [:], entries: [String: BookEntry] = [:]
        for note in notes {
            counts[note.entry.id, default: 0] += 1
            latest[note.entry.id] = max(latest[note.entry.id] ?? .distantPast, note.annotation.createdAt)
            entries[note.entry.id] = note.entry
        }
        return entries.values
            .sorted { l, r in
                let a = latest[l.id] ?? .distantPast, b = latest[r.id] ?? .distantPast
                return a != b ? a > b : l.id < r.id
            }
            .map { ($0, counts[$0.id] ?? 0) }
    }
}
