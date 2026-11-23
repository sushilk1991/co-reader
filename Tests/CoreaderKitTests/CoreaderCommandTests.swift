import Foundation
import Testing
@testable import CoreaderKit

/// Records what `coreader open` would have opened.
private final class OpenedLinks: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [URL] = []
    var urls: [URL] { lock.withLock { stored } }
    func append(_ url: URL) { lock.withLock { stored.append(url) } }
}

/// A small library: two books with notes, one without, and a CLI pointed at it.
private struct Fixture {
    let library = TestLibrary()
    let opened = OpenedLinks()
    let thinking: BookEntry
    let antifragile: BookEntry
    let dune: BookEntry

    init() throws {
        var thinking = try library.add("Thinking, Fast and Slow", authors: ["Daniel Kahneman"])
        thinking.book.status = .read
        thinking.book.rating = 5
        thinking.book.progress = 1
        try library.store.save(thinking.book, in: thinking.folder)
        var antifragile = try library.add("Antifragile", authors: ["Nassim Nicholas Taleb"])
        antifragile.book.status = .reading
        antifragile.book.rating = 3
        antifragile.book.progress = 0.416
        try library.store.save(antifragile.book, in: antifragile.folder)
        self.thinking = thinking
        self.antifragile = antifragile
        dune = try library.add("Dune", authors: ["Frank Herbert"])

        let notes = NotesStore()
        try notes.upsert(Annotation(
            id: "k10000000000", kind: .highlight, quote: "Nothing in life is as important as you think it is,\nwhile you are thinking about it.",
            note: "The focusing illusion.\n\nI fall for this weekly.", locator: Locator(page: 401, fraction: 0.8, label: "p. 402"),
            chapter: "Thinking About Life", tags: ["bias"], createdAt: date("2026-03-10T09:00:00Z")), in: thinking)
        try notes.upsert(Annotation(
            id: "k20000000000", kind: .note, note: "System 1 is the hero of the book.", locator: Locator(page: 20, fraction: 0.05, label: "p. 21"),
            chapter: "The Characters of the Story", createdAt: date("2026-01-05T09:00:00Z")), in: thinking)
        try notes.upsert(Annotation(
            id: "t10000000000", kind: .highlight, quote: "Wind extinguishes a candle and energizes fire.",
            locator: Locator(cfi: "epubcfi(/6/4!/4)", fraction: 0.02), createdAt: date("2026-06-01T12:00:00Z")), in: antifragile)
    }

    func run(_ arguments: String..., textCache: URL? = nil, isTTY: Bool = false) -> CoreaderCommand.Output {
        let opened = self.opened
        let command = CoreaderCommand(
            library: library.store,
            textStore: BookTextStore(cachesRoot: textCache ?? library.temp.url.appendingPathComponent("Caches")),
            isTTY: isTTY,
            timeZone: TimeZone(identifier: "UTC")!,
            opener: { opened.append($0) })
        return command.run(arguments)
    }

    func json(_ output: CoreaderCommand.Output) throws -> Any {
        try JSONSerialization.jsonObject(with: Data(output.stdout.utf8))
    }
}

@Suite struct CoreaderCommandTests {
    private let fixture: Fixture

    init() throws {
        fixture = try Fixture()
    }

    @Test func helpAndUsageErrors() {
        let overview = fixture.run()
        #expect(overview.exitCode == 0)
        #expect(overview.stdout.contains("Usage: coreader <command>"))
        #expect(fixture.run("--help").stdout == overview.stdout)
        #expect(fixture.run("help", "notes").stdout.hasPrefix("Usage: coreader notes <book>"))
        for command in ["path", "books", "notes", "search", "export", "text", "add", "open"] {
            let help = fixture.run(command, "--help")
            #expect(help.exitCode == 0)
            #expect(help.stdout.hasPrefix("Usage: coreader \(command)"))
            #expect(overview.stdout.contains("  \(command) "))
        }

        let unknown = fixture.run("frobnicate")
        #expect(unknown.exitCode == 2)
        #expect(unknown.stdout.isEmpty)
        #expect(unknown.stderr == "coreader: Unknown command 'frobnicate'.\nSee `coreader --help`.\n")

        let badOption = fixture.run("books", "--colour")
        #expect(badOption.exitCode == 2)
        #expect(badOption.stderr.contains("Unknown option '--colour'"))
        #expect(fixture.run("books", "--status").exitCode == 2)
        #expect(fixture.run("books", "--status", "sideways").stderr.contains("Use to-read, reading or read."))
        #expect(fixture.run("books", "--min-rating", "9").exitCode == 2)
        #expect(fixture.run("notes").exitCode == 2)
        #expect(fixture.run("search").exitCode == 2)
        #expect(fixture.run("path", "extra").exitCode == 2)
    }

    @Test func pathPrintsTheLibraryRoot() throws {
        #expect(fixture.run("path").stdout == fixture.library.store.root.path + "\n")
        let info = try #require(try fixture.json(fixture.run("path", "--json")) as? [String: Any])
        #expect(info["libraryRoot"] as? String == fixture.library.store.root.path)
        #expect(info["exists"] as? Bool == true)
    }

    @Test func booksListsAsATableWithoutANSIWhenNotATerminal() {
        let output = fixture.run("books")
        #expect(output.exitCode == 0)
        #expect(output.stdout == """
            SLUG\tSTATUS\tRATING\tPROGRESS\tNOTES\tTITLE\tAUTHORS
            antifragile\treading\t3\t42%\t1\tAntifragile\tNassim Nicholas Taleb
            dune\tto-read\t-\t0%\t0\tDune\tFrank Herbert
            thinking-fast-and-slow\tread\t5\t100%\t2\tThinking, Fast and Slow\tDaniel Kahneman

            """)
        #expect(!output.stdout.contains("\u{1B}"))
        #expect(fixture.run("books", isTTY: true).stdout.hasPrefix("\u{1B}[1mSLUG"))
    }

    @Test func booksFilters() throws {
        func slugs(_ arguments: String...) -> [String] {
            let command = CoreaderCommand(library: fixture.library.store)
            return command.run(["books"] + arguments).stdout.split(separator: "\n").dropFirst().map { String($0.prefix { $0 != "\t" }) }
        }
        #expect(slugs("--status", "read") == ["thinking-fast-and-slow"])
        #expect(slugs("--status=to-read") == ["dune"])
        #expect(slugs("--status", "reading") == ["antifragile"])
        #expect(slugs("--min-rating", "3") == ["antifragile", "thinking-fast-and-slow"])
        #expect(slugs("--min-rating", "4") == ["thinking-fast-and-slow"])
        #expect(slugs("--status", "reading", "--min-rating", "4").isEmpty)

        let none = fixture.run("books", "--status", "reading", "--min-rating", "4")
        #expect(none.exitCode == 0 && none.stdout.isEmpty && none.stderr == "No books match.\n")

        let records = try #require(try fixture.json(fixture.run("books", "--json", "--status", "read")) as? [[String: Any]])
        #expect(records.count == 1)
        let record = records[0]
        #expect(record["id"] as? String == fixture.thinking.book.id)
        #expect(record["slug"] as? String == "thinking-fast-and-slow")
        #expect(record["status"] as? String == "read")
        #expect(record["rating"] as? Int == 5)
        #expect(record["notes"] as? Int == 2)
        #expect(record["notesFile"] as? String == fixture.thinking.notesURL.path)
        #expect(record["link"] as? String == "coreader://open?book=\(fixture.thinking.book.id)")
        #expect(try fixture.json(fixture.run("books", "--json", "--min-rating", "5", "--status", "reading")) as? [Any] != nil)
    }

    @Test func notesPrintsTheMarkdownFile() throws {
        let file = try String(contentsOf: fixture.thinking.notesURL, encoding: .utf8)
        #expect(fixture.run("notes", "thinking-fast-and-slow").stdout == file)
        #expect(fixture.run("notes", fixture.thinking.book.id).stdout == file)
        #expect(fixture.run("notes", "fast", "and", "slow").stdout == file, "unquoted words are one title")
        #expect(fixture.run("notes", "THINKING").stdout == file)
        #expect(fixture.run("notes", String(fixture.thinking.book.id.prefix(8))).stdout == file)

        let empty = fixture.run("notes", "dune")
        #expect(empty.exitCode == 0 && empty.stdout.isEmpty)
        #expect(empty.stderr == "No notes yet for \"Dune\".\n")
    }

    @Test func notesJSONCarriesTextPositionsAndLinks() throws {
        let payload = try #require(try fixture.json(fixture.run("notes", "thinking", "--json")) as? [String: Any])
        #expect((payload["book"] as? [String: Any])?["title"] as? String == "Thinking, Fast and Slow")
        let annotations = try #require(payload["annotations"] as? [[String: Any]])
        #expect(annotations.map { $0["id"] as? String } == ["k20000000000", "k10000000000"])
        let last = annotations[1]
        #expect(last["quote"] as? String == "Nothing in life is as important as you think it is,\nwhile you are thinking about it.")
        #expect(last["note"] as? String == "The focusing illusion.\n\nI fall for this weekly.")
        #expect(last["position"] as? String == "p. 402")
        #expect(last["chapter"] as? String == "Thinking About Life")
        #expect(last["tags"] as? [String] == ["bias"])
        #expect(last["createdAt"] as? String == "2026-03-10T09:00:00Z")
        #expect(last["link"] as? String == "coreader://open?book=\(fixture.thinking.book.id)&a=k10000000000")
        #expect((try fixture.json(fixture.run("notes", "dune", "--json")) as? [String: Any])?["annotations"] as? [Any] != nil)
    }

    @Test func unknownAndAmbiguousBooksAreClearErrors() throws {
        let missing = fixture.run("notes", "moby dick")
        #expect(missing.exitCode == 1)
        #expect(missing.stdout.isEmpty)
        #expect(missing.stderr == "coreader: No book matches \"moby dick\". List the library with `coreader books`.\n")

        try fixture.library.add("Dune Messiah")
        #expect(fixture.run("open", "dune").exitCode == 0, "an exact slug wins over a title substring")
        let ambiguous = fixture.run("notes", "un")
        #expect(ambiguous.exitCode == 1)
        #expect(ambiguous.stderr.contains("\"un\" matches 2 books"))
        #expect(ambiguous.stderr.contains("  dune\tDune\n  dune-messiah\tDune Messiah"))
    }

    @Test func searchPrintsQuotesNotesAndLinks() throws {
        let output = fixture.run("search", "IMPORTANT")
        #expect(output.stdout == """
            Thinking, Fast and Slow — Daniel Kahneman (p. 402)
            > Nothing in life is as important as you think it is,
            > while you are thinking about it.
            The focusing illusion.

            I fall for this weekly.
            Tags: bias
            coreader://open?book=\(fixture.thinking.book.id)&a=k10000000000

            """)
        let none = fixture.run("search", "zebra")
        #expect(none.exitCode == 0 && none.stdout.isEmpty && none.stderr == "No notes match \"zebra\".\n")

        let hits = try #require(try fixture.json(fixture.run("search", "--json", "candle", "fire")) as? [[String: Any]])
        #expect(hits.count == 1)
        #expect((hits[0]["book"] as? [String: Any])?["slug"] as? String == "antifragile")
        #expect((hits[0]["annotation"] as? [String: Any])?["position"] as? String == "2%")
        #expect(try fixture.json(fixture.run("search", "zebra", "--json")) as? [Any] != nil)
    }

    @Test func exportIsOneDocumentInTheReadersWords() {
        let output = fixture.run("export")
        #expect(output.exitCode == 0)
        let thinking = fixture.thinking.book.id, antifragile = fixture.antifragile.book.id
        #expect(output.stdout == """
            # Reading notes

            3 notes from 2 books. Blockquotes are passages from the books; the text under them is the reader's own. Each link opens the passage in Coreader.

            ## Antifragile

            By Nassim Nicholas Taleb · Status: reading · Rating: 3/5 · Book: coreader://open?book=\(antifragile)

            > Wind extinguishes a candle and energizes fire.

            [2%](coreader://open?book=\(antifragile)&a=t10000000000)

            ## Thinking, Fast and Slow

            By Daniel Kahneman · Status: read · Rating: 5/5 · Book: coreader://open?book=\(thinking)

            ### The Characters of the Story

            System 1 is the hero of the book.

            [p. 21](coreader://open?book=\(thinking)&a=k20000000000)

            ### Thinking About Life

            > Nothing in life is as important as you think it is,
            > while you are thinking about it.

            The focusing illusion.

            I fall for this weekly.

            Tags: bias

            [p. 402](coreader://open?book=\(thinking)&a=k10000000000)

            """)
        #expect(!output.stdout.contains("<!-- coreader"), "the export is for reading, not for the app")
    }

    @Test func exportFiltersByBookAndDate() {
        let oneBook = fixture.run("export", "--book", "antifragile")
        #expect(oneBook.stdout.contains("1 note from 1 book."))
        #expect(!oneBook.stdout.contains("Thinking, Fast and Slow"))

        let recent = fixture.run("export", "--since", "2026-03-10")
        #expect(recent.stdout.contains("2 notes from 2 books, written since 2026-03-10."))
        #expect(recent.stdout.contains("focusing illusion") && !recent.stdout.contains("System 1 is the hero"))
        #expect(fixture.run("export", "--since=2026-03-11").stdout.contains("1 note from 1 book"))

        let nothing = fixture.run("export", "--since", "2030-01-01")
        #expect(nothing.exitCode == 0 && nothing.stdout.isEmpty && nothing.stderr == "No notes to export.\n")
        #expect(fixture.run("export", "--book", "dune").stderr == "No notes to export.\n")
        #expect(fixture.run("export", "--since", "last week").exitCode == 2)
        #expect(fixture.run("export", "--since", "2026-02-31").exitCode == 2)
        #expect(fixture.run("export", "--book", "nope").exitCode == 1)
    }

    @Test func textPrintsSavedSectionsAndExplainsWhenThereAreNone() throws {
        let caches = fixture.library.temp.url.appendingPathComponent("Caches")
        let missing = fixture.run("text", "dune")
        #expect(missing.exitCode == 1)
        #expect(missing.stdout.isEmpty)
        #expect(missing.stderr.contains("No extracted text for \"Dune\" yet."))
        #expect(missing.stderr.contains("coreader open dune"))
        #expect(missing.stderr.contains(fixture.dune.fileURL.path))

        try BookTextStore(cachesRoot: caches).save([
            .init(index: 0, title: "Book One: Dune", locator: Locator(cfi: "epubcfi(/6/2!)", fraction: 0), text: "A beginning is the time for taking the most delicate care."),
            .init(index: 1, title: "Book Two: Muad'Dib", locator: Locator(cfi: "epubcfi(/6/4!)", fraction: 0.5), text: "When my father, the Padishah Emperor…"),
        ], for: fixture.dune.book)
        let id = fixture.dune.book.id

        #expect(fixture.run("text", "dune", "--list").stdout == "SECTION\tCHARACTERS\tTITLE\n1\t58\tBook One: Dune\n2\t37\tBook Two: Muad'Dib\n")
        #expect(fixture.run("text", "dune", "--section", "2").stdout
            == "# Book Two: Muad'Dib\n\n[Open in Coreader](coreader://open?book=\(id)&cfi=epubcfi(/6/4!))\n\nWhen my father, the Padishah Emperor…\n")
        let all = fixture.run("text", "dune").stdout
        #expect(all.hasPrefix("# Book One: Dune\n\n[Open in Coreader]"))
        #expect(all.contains("delicate care.\n\n# Book Two: Muad'Dib\n"))

        let outOfRange = fixture.run("text", "dune", "--section", "3")
        #expect(outOfRange.exitCode == 1)
        #expect(outOfRange.stderr.contains("has sections 1 to 2; there is no section 3"))

        let records = try #require(try fixture.json(fixture.run("text", "dune", "--json", "--section=1")) as? [[String: Any]])
        #expect(records.count == 1)
        #expect(records[0]["text"] as? String == "A beginning is the time for taking the most delicate care.")
        #expect((records[0]["file"] as? String)?.hasSuffix("/text/\(id)/001-book-one-dune.md") == true)
        let listed = try #require(try fixture.json(fixture.run("text", "dune", "--json", "--list")) as? [[String: Any]])
        #expect(listed.count == 2 && listed[0]["text"] == nil)
    }

    #if canImport(PDFKit)
    @Test func textExtractsPDFsOnFirstUse() throws {
        let pdf = fixture.library.temp.url.appendingPathComponent("paper.pdf")
        makePDF(pages: ["Attention is all you need", "Scaled dot-product attention"], at: pdf)
        let entry = try fixture.library.store.importFile(at: pdf, metadata: ImportMetadata(title: "Attention Paper", kind: .paper))

        let first = fixture.run("text", "attention-paper", "--section", "2")
        #expect(first.exitCode == 0)
        #expect(first.stderr == "Extracted text from 2 PDF pages.\n")
        #expect(first.stdout.hasPrefix("# Page 2\n\n[Open in Coreader](coreader://open?book=\(entry.book.id)&page=2)\n\n"))
        #expect(first.stdout.contains("Scaled dot-product attention"))
        // The second call reads the cache.
        #expect(fixture.run("text", "attention-paper", "--list").stderr.isEmpty)
    }
    #endif

    @Test func addImportsFilesAndReportsDuplicates() throws {
        let temp = fixture.library.temp
        let new = temp.file("in/New Arrival.epub", "brand new")
        let copy = temp.file("in/copy of new.epub", "brand new")
        let bad = temp.file("in/notes.txt", "text")

        let output = fixture.run("add", new.path, copy.path, bad.path, temp.url.appendingPathComponent("missing.pdf").path)
        #expect(output.exitCode == 1, "any failure makes the exit code non-zero")
        #expect(output.stdout == "added\tnew-arrival\tNew Arrival\nexists\tnew-arrival\tNew Arrival\n")
        #expect(output.stderr.contains("notes.txt: Coreader cannot open .txt files."))
        #expect(output.stderr.contains("missing.pdf: No file at"))
        #expect(try fixture.library.store.allBooks().count == 4)

        let titled = fixture.run("add", temp.file("in/x.pdf", "a paper").path, "--title", "A Paper", "--author", "Ann", "--author=Bob", "--kind", "paper", "--json")
        #expect(titled.exitCode == 0)
        let records = try #require(try fixture.json(titled) as? [[String: Any]])
        #expect(records[0]["added"] as? Bool == true)
        let book = try #require(records[0]["book"] as? [String: Any])
        #expect(book["slug"] as? String == "a-paper")
        #expect(book["authors"] as? [String] == ["Ann", "Bob"])
        #expect(book["kind"] as? String == "paper")

        #expect(fixture.run("add").exitCode == 2)
        #expect(fixture.run("add", new.path, copy.path, "--title", "Both").exitCode == 2)
        #expect(fixture.run("add", new.path, "--kind", "scroll").exitCode == 2)
    }

    @Test func addWorksOnALibraryThatDoesNotExistYet() throws {
        let temp = TempDirectory()
        let store = LibraryStore(root: temp.url.appendingPathComponent("fresh/Coreader"))
        let command = CoreaderCommand(library: store, textStore: BookTextStore(cachesRoot: temp.url.appendingPathComponent("caches")))
        #expect(command.run(["books"]).stderr == "No books match.\n")
        #expect(!FileManager.default.fileExists(atPath: store.root.path), "reading never creates the library")
        #expect(command.run(["add", temp.file("first.epub", "x").path]).stdout == "added\tfirst\tfirst\n")
        #expect(FileManager.default.fileExists(atPath: store.readmeURL.path))
    }

    @Test func openHandsADeepLinkToTheOpener() {
        let id = fixture.dune.book.id
        #expect(fixture.run("open", "dune").stdout == "coreader://open?book=\(id)\n")
        #expect(fixture.run("open", "dune", "--page", "42").stdout == "coreader://open?book=\(id)&page=42\n")
        #expect(fixture.opened.urls.map(\.absoluteString) == ["coreader://open?book=\(id)", "coreader://open?book=\(id)&page=42"])
        #expect(DeepLink(url: fixture.opened.urls[1]) == .location(bookID: id, locator: Locator(page: 41)))

        #expect(fixture.run("open", "dune", "--page", "0").exitCode == 2)
        #expect(fixture.run("open", "nope").exitCode == 1)
        #expect(fixture.opened.urls.count == 2)

        let failing = CoreaderCommand(library: fixture.library.store, opener: { _ in throw CoreaderCommand.Failure("Could not open it.") })
        let output = failing.run(["open", "dune"])
        #expect(output.exitCode == 1 && output.stdout.isEmpty && output.stderr == "coreader: Could not open it.\n")
    }
}
