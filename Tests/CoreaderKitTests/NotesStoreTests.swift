import Foundation
import Testing
@testable import CoreaderKit

private func note(
    _ id: String, at fraction: Double, quote: String = "", note: String = "", chapter: String? = nil, tags: [String] = [],
    created: String = "2026-11-20T08:00:00Z"
) -> Annotation {
    Annotation(
        id: id, kind: quote.isEmpty ? .note : .highlight, quote: quote, note: note,
        locator: Locator(fraction: fraction), chapter: chapter, tags: tags, createdAt: date(created))
}

@Suite struct NotesStoreTests {
    let library = TestLibrary()
    let notes = NotesStore()

    @Test func loadIsEmptyWithoutANotesFile() throws {
        let entry = try library.add("Quiet Book")
        #expect(try notes.load(entry).isEmpty)
        try notes.remove(id: "nothing", from: entry)
        #expect(!FileManager.default.fileExists(atPath: entry.notesURL.path), "reading or removing never creates the file")
    }

    @Test func upsertInsertsUpdatesAndKeepsReadingOrder() throws {
        let entry = try library.add("Ordered", authors: ["A. Writer"])
        try notes.upsert(note("late00000000", at: 0.8, quote: "Late"), in: entry)
        try notes.upsert(note("early0000000", at: 0.1, quote: "Early", note: "first draft"), in: entry)
        try notes.upsert(note("middle000000", at: 0.5, note: "bare note"), in: entry)
        #expect(try notes.load(entry).map(\.id) == ["early0000000", "middle000000", "late00000000"])

        var changed = try notes.load(entry)[0]
        changed.note = "second draft"
        changed.color = .pink
        changed.tags = ["revised"]
        try notes.upsert(changed, in: entry)
        let loaded = try notes.load(entry)
        #expect(loaded.count == 3)
        #expect(loaded[0] == changed)

        let markdown = try String(contentsOf: entry.notesURL, encoding: .utf8)
        #expect(markdown.hasPrefix("---\ntitle: \"Ordered\"\nauthor:\n  - \"A. Writer\"\ncoreader_id: \(entry.book.id)\nsource: coreader\nupdated: 20"))
        #expect(markdown.contains("\n# Ordered\n"))
        #expect(try FileManager.default.contentsOfDirectory(atPath: entry.folder.path).sorted() == ["book.json", "notes.md", "ordered.epub"])
    }

    @Test func removeDeletesOnlyThatAnnotation() throws {
        let entry = try library.add("Removal")
        for (n, id) in ["a00000000000", "b00000000000", "c00000000000"].enumerated() {
            try notes.upsert(note(id, at: Double(n) / 10, quote: "Quote \(n)"), in: entry)
        }
        try notes.remove(id: "b00000000000", from: entry)
        try notes.remove(id: "not-there", from: entry)
        #expect(try notes.load(entry).map(\.id) == ["a00000000000", "c00000000000"])
        #expect(!(try String(contentsOf: entry.notesURL, encoding: .utf8)).contains("Quote 1"))
    }

    @Test func handEditsSurviveTheNextAppWrite() throws {
        let entry = try library.add("Edited By Hand")
        try notes.upsert(note("a00000000000", at: 0.1, quote: "Original quote.", note: "Original note.", chapter: "One"), in: entry)
        try notes.upsert(note("b00000000000", at: 0.2, quote: "Second quote.", chapter: "One"), in: entry)

        // A person opens notes.md in an editor: fixes the quote, rewrites the note, adds
        // an intro, a paragraph between notes, a summary, and an Obsidian property.
        var markdown = try String(contentsOf: entry.notesURL, encoding: .utf8)
        markdown = markdown
            .replacingOccurrences(of: "source: coreader\n", with: "source: coreader\ntags: [books, favourites]\n")
            .replacingOccurrences(of: "# Edited By Hand\n", with: "# Edited By Hand\n\nStarted on the train.\n")
            .replacingOccurrences(of: "> Original quote.", with: "> Original quote, with the typo fixed.")
            .replacingOccurrences(of: "Original note.", with: "A much better note.\n\nWith a second paragraph.")
            .replacingOccurrences(of: "&a=a00000000000)\n", with: "&a=a00000000000)\n\nAn aside of my own.\n")
        markdown += "\n## My summary\n\nWorth rereading.\n"
        try Data(markdown.utf8).write(to: entry.notesURL)

        // The app then adds a highlight, changes a colour and deletes a note.
        try notes.upsert(note("c00000000000", at: 0.9, quote: "Third quote.", chapter: "Two"), in: entry)
        var first = try notes.load(entry)[0]
        #expect(first.quote == "Original quote, with the typo fixed.")
        #expect(first.note == "A much better note.\n\nWith a second paragraph.")
        first.color = .green
        try notes.upsert(first, in: entry)
        try notes.remove(id: "b00000000000", from: entry)

        let after = try String(contentsOf: entry.notesURL, encoding: .utf8)
        let document = try notes.document(for: entry)
        #expect(document.annotations.map(\.id) == ["a00000000000", "c00000000000"])
        #expect(document.annotations[0].quote == "Original quote, with the typo fixed.")
        #expect(document.annotations[0].note == "A much better note.\n\nWith a second paragraph.")
        #expect(document.annotations[0].color == .green)
        #expect(document.preamble == "Started on the train.")
        #expect(document.interleaved == ["a00000000000": "An aside of my own."])
        #expect(document.trailer == "## My summary\n\nWorth rereading.")
        #expect(document.extraFrontMatter == ["tags: [books, favourites]"])
        // The summary stays at the end, after the highlight that was added later.
        let third = try #require(after.range(of: "Third quote."))
        let summary = try #require(after.range(of: "## My summary"))
        #expect(third.lowerBound < summary.lowerBound)
        #expect(after.hasSuffix("## My summary\n\nWorth rereading.\n"))
    }

    @Test func removingAnAnnotationKeepsTheTextWrittenUnderIt() throws {
        let entry = try library.add("Orphans")
        try notes.upsert(note("a00000000000", at: 0.1, quote: "A"), in: entry)
        try notes.upsert(note("b00000000000", at: 0.2, quote: "B"), in: entry)
        var markdown = try String(contentsOf: entry.notesURL, encoding: .utf8)
        markdown = markdown
            .replacingOccurrences(of: "&a=a00000000000)\n", with: "&a=a00000000000)\n\nUnder A.\n")
            .replacingOccurrences(of: "&a=b00000000000)\n", with: "&a=b00000000000)\n\nUnder B.\n")
        try Data(markdown.utf8).write(to: entry.notesURL)
        // "Under B." follows the last block, so it is the trailer; add C to make it interleaved.
        try notes.upsert(note("c00000000000", at: 0.3, quote: "C"), in: entry)
        #expect(try notes.document(for: entry).trailer == "Under B.")

        try notes.remove(id: "a00000000000", from: entry)
        var document = try notes.document(for: entry)
        #expect(document.preamble == "Under A.")
        try notes.remove(id: "c00000000000", from: entry)
        try notes.remove(id: "b00000000000", from: entry)
        document = try notes.document(for: entry)
        #expect(document.annotations.isEmpty)
        let text = try String(contentsOf: entry.notesURL, encoding: .utf8)
        #expect(text.contains("Under A.") && text.contains("Under B."))
    }

    @Test func writeFollowsTheBookWhenItIsRenamed() throws {
        var entry = try library.add("Working Title", authors: ["First Author"])
        try notes.upsert(note("a00000000000", at: 0.1, quote: "Q"), in: entry)
        entry.book.title = "Final Title"
        entry.book.authors = ["First Author", "Second Author"]
        try library.store.save(entry.book, in: entry.folder)
        try notes.upsert(note("b00000000000", at: 0.2, quote: "R"), in: entry)

        let markdown = try String(contentsOf: entry.notesURL, encoding: .utf8)
        #expect(markdown.contains("title: \"Final Title\""))
        #expect(markdown.contains("  - \"Second Author\""))
        #expect(markdown.contains("\n# Final Title\n"))
        #expect(!markdown.contains("Working Title"), "the old heading is replaced, not kept as user text")
        #expect(try notes.load(entry).count == 2)
    }

    @Test func saveAssetReturnsUniqueReadableNames() throws {
        let entry = try library.add("Pictures")
        let first = try notes.saveAsset(Data([1]), suggestedName: "Figure 3: The Müller-Lyer Illusion", fileExtension: "PNG", in: entry)
        let second = try notes.saveAsset(Data([2]), suggestedName: "Figure 3: The Müller-Lyer Illusion", fileExtension: ".png", in: entry)
        let unnamed = try notes.saveAsset(Data([3]), suggestedName: "", fileExtension: "", in: entry)
        #expect(first == "figure-3-the-muller-lyer-illusion.png")
        #expect(second == "figure-3-the-muller-lyer-illusion-2.png")
        #expect(unnamed == "image.png")
        #expect(try Data(contentsOf: entry.assetsURL.appendingPathComponent(first)) == Data([1]))
        #expect(try Data(contentsOf: entry.assetsURL.appendingPathComponent(second)) == Data([2]))

        var image = Annotation(kind: .image, quote: "Figure 3", locator: Locator(page: 2, fraction: 0.3), createdAt: date("2026-01-01T00:00:00Z"))
        image.asset = first
        try notes.upsert(image, in: entry)
        #expect(try String(contentsOf: entry.notesURL, encoding: .utf8).contains("![Figure 3](assets/\(first))"))
        #expect(try notes.load(entry) == [image])
    }

    @Test func allAndSearchSpanTheLibrary() throws {
        let kahneman = try library.add("Thinking, Fast and Slow")
        let taleb = try library.add("Antifragile")
        try library.add("No Notes Here")
        try notes.upsert(note("k10000000000", at: 0.2, quote: "Nothing in life is as important as you think it is.", note: "The focusing illusion", tags: ["bias"]), in: kahneman)
        try notes.upsert(note("k20000000000", at: 0.1, quote: "A naïve café observation.", note: "", tags: ["Résumé"]), in: kahneman)
        try notes.upsert(note("t10000000000", at: 0.5, quote: "Wind extinguishes a candle and energizes fire.", note: "IMPORTANT: this is the thesis", tags: ["fragility"]), in: taleb)

        let all = try notes.all(in: library.store)
        #expect(all.map(\.annotation.id) == ["t10000000000", "k20000000000", "k10000000000"])
        #expect(all.map(\.entry.book.title) == ["Antifragile", "Thinking, Fast and Slow", "Thinking, Fast and Slow"])

        func ids(_ query: String) throws -> [String] { try notes.search(query, in: library.store).map(\.annotation.id) }
        #expect(try ids("important") == ["t10000000000", "k10000000000"], "case-insensitive, quote and note")
        #expect(try ids("NAIVE cafe") == ["k20000000000"], "accents are ignored")
        #expect(try ids("resume") == ["k20000000000"], "tags are searched")
        #expect(try ids("candle thesis fragility") == ["t10000000000"], "every word must match, across fields")
        #expect(try ids("candle illusion").isEmpty)
        #expect(try ids("   ").isEmpty)
        #expect(try ids("zebra").isEmpty)
    }
}
