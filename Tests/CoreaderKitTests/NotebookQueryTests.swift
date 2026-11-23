import Foundation
import Testing
@testable import CoreaderKit

@Suite struct NotebookQueryTests {
    private static func entry(_ id: String, _ title: String, author: String = "") -> BookEntry {
        var book = Book(title: title, authors: author.isEmpty ? [] : [author], format: .epub, fileName: "\(id).epub")
        book.id = id
        return BookEntry(book: book, folder: URL(fileURLWithPath: "/library/Books/\(id)"))
    }

    private static func note(
        _ entry: BookEntry, _ id: String, _ kind: AnnotationKind = .highlight, quote: String = "", note: String = "",
        color: HighlightColor = .yellow, chapter: String? = nil, at fraction: Double = 0, created: String
    ) -> LibraryNote {
        LibraryNote(entry: entry, annotation: Annotation(
            id: id, kind: kind, quote: quote, note: note, color: color, locator: Locator(fraction: fraction),
            chapter: chapter, asset: kind == .image ? "\(id).png" : nil, createdAt: date(created)))
    }

    static let walden = entry("walden", "Walden", author: "Henry David Thoreau")
    static let paper = entry("attention", "Attention Is All You Need")
    /// Reading order within each book, as `NotesStore.all` returns it.
    static let all = [
        note(walden, "w1", quote: "Our garments become assimilated to ourselves", chapter: "Economy", at: 0.1, created: "2026-11-01T08:00:00Z"),
        note(walden, "w2", quote: "Simplify, simplify", note: "Résumé of the whole book", color: .green, at: 0.3, created: "2026-11-05T08:00:00Z"),
        note(walden, "w3", .image, quote: "The cabin", at: 0.5, created: "2026-11-02T08:00:00Z"),
        note(paper, "p1", .note, note: "Compare with RNN attention", at: 0.2, created: "2026-11-03T08:00:00Z"),
        note(paper, "p2", quote: "Self-attention relates positions", color: .blue, at: 0.4, created: "2026-11-04T08:00:00Z"),
    ]

    private func ids(_ change: (inout NotebookQuery) -> Void) -> [String] {
        var query = NotebookQuery()
        change(&query)
        return query.apply(to: Self.all).map(\.annotation.id)
    }

    @Test func byBookPutsTheMostRecentlyAnnotatedBookFirstAndKeepsReadingOrder() {
        #expect(ids { _ in } == ["w1", "w2", "w3", "p1", "p2"])
    }

    @Test func aBookKeepsItsPlaceWhenItsNewestNoteIsFilteredOut() {
        // Hiding Walden's newest note (w2) must not drop Walden below the paper.
        #expect(ids { $0.kind = .highlights; $0.text = "at" } == ["w1", "p2"])
    }

    @Test func sortsByDate() {
        #expect(ids { $0.sort = .newest } == ["w2", "p2", "p1", "w3", "w1"])
        #expect(ids { $0.sort = .oldest } == ["w1", "w3", "p1", "p2", "w2"])
    }

    @Test func filtersByBookKindAndColour() {
        #expect(ids { $0.bookID = "attention" } == ["p1", "p2"])
        #expect(ids { $0.kind = .highlights } == ["w1", "w2", "p2"])
        #expect(ids { $0.kind = .notes } == ["w2", "p1"], "a highlight with words on it counts as a note")
        #expect(ids { $0.kind = .images } == ["w3"])
        #expect(ids { $0.color = .yellow } == ["w1"], "images and bare notes carry a default colour that is never shown")
        #expect(ids { $0.color = .blue; $0.bookID = "walden" }.isEmpty)
    }

    @Test func searchMatchesEveryWordAcrossQuoteNoteChapterAndBook() {
        #expect(ids { $0.text = "resume BOOK" } == ["w2"], "accents and case are ignored")
        #expect(ids { $0.text = "economy" } == ["w1"])
        #expect(ids { $0.text = "thoreau cabin" } == ["w3"])
        #expect(ids { $0.text = "attention" } == ["p1", "p2"])
        #expect(ids { $0.text = "attention simplify" }.isEmpty)
        #expect(ids { $0.text = "   " }.count == 5)
    }

    @Test func knowsWhenItIsFiltering() {
        var query = NotebookQuery()
        query.sort = .newest
        #expect(!query.isFiltering)
        query.text = " x "
        #expect(query.isFiltering)
    }

    @Test func listsBooksWithCountsMostRecentFirst() {
        let books = NotebookQuery.books(in: Self.all)
        #expect(books.map(\.entry.id) == ["walden", "attention"])
        #expect(books.map(\.count) == [3, 2])
    }

    @Test func sameAnnotationIDInTwoBooksStaysDistinct() {
        let a = Self.note(Self.walden, "same", quote: "A", created: "2026-11-01T08:00:00Z")
        let b = Self.note(Self.paper, "same", quote: "B", created: "2026-11-01T08:00:00Z")
        #expect(a.id != b.id)
    }
}
