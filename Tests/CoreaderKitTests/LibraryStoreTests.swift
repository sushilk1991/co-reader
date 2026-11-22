import Foundation
import Testing
@testable import CoreaderKit

@Suite struct LibraryConfigTests {
    @Test func savesAPlainPathAndLoadsItBack() throws {
        let temp = TempDirectory()
        let configURL = temp.url.appendingPathComponent("Support/Coreader/config.json")
        let root = temp.url.appendingPathComponent("My Library", isDirectory: true)
        try LibraryConfig(libraryRoot: root).save(to: configURL)

        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: configURL)) as? [String: String]
        #expect(json == ["libraryRoot": root.path])
        #expect(LibraryConfig.load(from: configURL).libraryRoot.path == root.path)
    }

    @Test func environmentOverridesTheConfigFile() throws {
        let temp = TempDirectory()
        let configURL = temp.url.appendingPathComponent("config.json")
        try LibraryConfig(libraryRoot: temp.url.appendingPathComponent("configured")).save(to: configURL)
        let loaded = LibraryConfig.load(from: configURL, environment: ["COREADER_LIBRARY": temp.url.appendingPathComponent("override").path])
        #expect(loaded.libraryRoot.lastPathComponent == "override")
        // An empty variable is the same as no variable.
        #expect(LibraryConfig.load(from: configURL, environment: ["COREADER_LIBRARY": " "]).libraryRoot.lastPathComponent == "configured")
    }

    @Test func missingOrDamagedConfigFallsBackToTheDefaultRoot() throws {
        let temp = TempDirectory()
        let home = temp.url.appendingPathComponent("home", isDirectory: true)
        let missing = temp.url.appendingPathComponent("nope.json")
        #expect(LibraryConfig.load(from: missing, home: home).libraryRoot.path == home.appendingPathComponent("Documents/Coreader").path)

        let damaged = temp.file("damaged.json", "{ not json")
        #expect(LibraryConfig.load(from: damaged, home: home).libraryRoot.path == home.appendingPathComponent("Documents/Coreader").path)
    }

    @Test func defaultRootPrefersICloudDriveWhenItExists() throws {
        let temp = TempDirectory()
        #expect(LibraryConfig.defaultRoot(home: temp.url).path == temp.url.appendingPathComponent("Documents/Coreader").path)
        let drive = temp.url.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs", isDirectory: true)
        try FileManager.default.createDirectory(at: drive, withIntermediateDirectories: true)
        #expect(LibraryConfig.defaultRoot(home: temp.url).path == drive.appendingPathComponent("Coreader").path)
    }

    @Test func readsFileURLsAndTildePaths() throws {
        let temp = TempDirectory()
        let fileURLConfig = temp.file("a.json", #"{"libraryRoot": "file:///tmp/coreader-lib"}"#)
        #expect(LibraryConfig.load(from: fileURLConfig).libraryRoot.path == "/tmp/coreader-lib")
        let tildeConfig = temp.file("b.json", #"{"libraryRoot": "~/Books"}"#)
        #expect(LibraryConfig.load(from: tildeConfig).libraryRoot.path == NSHomeDirectory() + "/Books")
    }
}

@Suite struct SlugAndHashTests {
    @Test(arguments: [
        ("Thinking, Fast and Slow", "thinking-fast-and-slow"),
        ("  Gödel, Escher, Bach: an Eternal Golden Braid ", "godel-escher-bach-an-eternal-golden-braid"),
        ("Don’t Make Me Think", "dont-make-me-think"),
        ("Straße & Æther", "strasse-aether"),
        ("C++ / Rust: 2nd_edition.pdf", "c-rust-2nd-edition-pdf"),
        ("!!!", "untitled"),
        ("", "untitled"),
    ])
    func slugs(input: String, expected: String) {
        #expect(Slug.make(input) == expected)
    }

    @Test func slugsAreASCIIForAnyScript() {
        let slug = Slug.make("戦争と平和 Война и мир")
        #expect(!slug.isEmpty && slug != "untitled")
        #expect(slug.unicodeScalars.allSatisfy { ("a"..."z").contains($0) || ("0"..."9").contains($0) || $0 == "-" })
    }

    @Test func longSlugsAreCutAtAWordAndNeverEndWithAHyphen() {
        let slug = Slug.make(String(repeating: "wonderful words ", count: 20), maxLength: 30)
        #expect(slug.count <= 30)
        #expect(!slug.hasSuffix("-"))
        #expect(slug == "wonderful-words-wonderful")
        #expect(Slug.make(String(repeating: "a", count: 100), maxLength: 10) == "aaaaaaaaaa")
    }

    @Test func sha256MatchesKnownVectors() throws {
        #expect(SHA256.hex(of: Data()) == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
        #expect(SHA256.hex(of: Data("abc".utf8)) == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        #expect(SHA256.hex(of: Data("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq".utf8))
            == "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1")
        // One million 'a', fed in uneven pieces so block boundaries are crossed every way.
        var hasher = SHA256()
        var remaining = 1_000_000
        var size = 1
        while remaining > 0 {
            let take = min(size, remaining)
            hasher.update(Data(repeating: 0x61, count: take))
            remaining -= take
            size = size % 200 + 7
        }
        #expect(hasher.finalize() == "cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0")

        let temp = TempDirectory()
        let file = temp.file("abc.txt", "abc")
        #expect(try SHA256.hex(ofFileAt: file) == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }
}

@Suite struct LibraryStoreTests {
    @Test func prepareCreatesTheLayoutAndAVersionedReadme() throws {
        let library = TestLibrary()
        try library.store.prepare()
        let readme = try String(contentsOf: library.store.readmeURL, encoding: .utf8)
        #expect(readme.hasPrefix("<!-- coreader-readme v\(LibraryReadme.version) -->\n# Coreader library"))
        #expect(readme.contains("notes.md"))
        #expect(readme.contains("coreader://open?book=<id>&a=<annotation>"))
        var isDirectory: ObjCBool = false
        #expect(FileManager.default.fileExists(atPath: library.store.booksRoot.path, isDirectory: &isDirectory) && isDirectory.boolValue)
        #expect(try library.store.allBooks().isEmpty)
    }

    @Test func prepareReplacesAnOutdatedReadmeButNotANewerOne() throws {
        let library = TestLibrary()
        try library.store.prepare()

        try Data("old text without a marker".utf8).write(to: library.store.readmeURL)
        try library.store.prepare()
        #expect(try String(contentsOf: library.store.readmeURL, encoding: .utf8) == LibraryReadme.text)

        let newer = "<!-- coreader-readme v\(LibraryReadme.version + 1) -->\nfrom a newer app"
        try Data(newer.utf8).write(to: library.store.readmeURL)
        try library.store.prepare()
        #expect(try String(contentsOf: library.store.readmeURL, encoding: .utf8) == newer)
    }

    @Test func allBooksOnAMissingLibraryIsEmptyAndCreatesNothing() throws {
        let library = TestLibrary()
        #expect(try library.store.allBooks().isEmpty)
        #expect(try library.store.entry(id: "x") == nil)
        #expect(!FileManager.default.fileExists(atPath: library.store.root.path))
    }

    @Test func importCopiesTheFileAndWritesBookJSON() throws {
        let library = TestLibrary()
        let source = library.temp.file("Downloads/Some File.EPUB", "epub bytes")
        let metadata = ImportMetadata(
            title: "Thinking, Fast and Slow", authors: ["Daniel Kahneman"], summary: "Two systems.",
            publisher: "FSG", year: 2011, language: "en", pageCount: 499)
        let entry = try library.store.importFile(at: source, metadata: metadata)

        #expect(entry.folder.path == library.store.booksRoot.appendingPathComponent("thinking-fast-and-slow").path)
        #expect(entry.book.fileName == "thinking-fast-and-slow.epub")
        #expect(try String(contentsOf: entry.fileURL, encoding: .utf8) == "epub bytes")
        #expect(FileManager.default.fileExists(atPath: source.path), "import copies, it does not move")
        #expect(entry.book.format == .epub)
        #expect(entry.book.kind == .book)
        #expect(entry.book.status == .toRead)
        #expect(entry.book.authors == ["Daniel Kahneman"])
        #expect(entry.book.year == 2011)
        #expect(entry.book.pageCount == 499)
        #expect(entry.book.contentHash == SHA256.hex(of: Data("epub bytes".utf8)))

        let stored = try #require(try library.store.entry(id: entry.book.id))
        #expect(stored.book.title == "Thinking, Fast and Slow")
        #expect(stored.book.contentHash == entry.book.contentHash)
        #expect(abs(stored.book.addedAt.timeIntervalSince(entry.book.addedAt)) < 1)

        // No staging folders left behind.
        let names = try FileManager.default.contentsOfDirectory(atPath: library.store.booksRoot.path)
        #expect(names == ["thinking-fast-and-slow"])
    }

    @Test func importFallsBackToTheFileNameAndInfersKind() throws {
        let library = TestLibrary()
        let pdf = try library.store.importFile(at: library.temp.file("in/Attention Is All You Need.pdf", "pdf"), metadata: ImportMetadata())
        #expect(pdf.book.title == "Attention Is All You Need")
        #expect(pdf.folder.lastPathComponent == "attention-is-all-you-need")
        #expect(pdf.book.format == .pdf)

        let article = try library.store.importFile(at: library.temp.file("in/saved page.html", "<html>"), metadata: ImportMetadata(title: "   "))
        #expect(article.book.title == "saved page")
        #expect(article.book.kind == .article)

        let paper = try library.store.importFile(at: library.temp.file("in/x.pdf", "other pdf"), metadata: ImportMetadata(title: "★", kind: .paper, arxivID: "1706.03762"))
        #expect(paper.book.kind == .paper)
        #expect(paper.book.arxivID == "1706.03762")
        #expect(paper.folder.lastPathComponent == "x", "a title with no usable characters falls back to the file name")
    }

    @Test func importingTheSameContentTwiceReturnsTheExistingBook() throws {
        let library = TestLibrary()
        let first = try library.store.importFile(at: library.temp.file("a/one.epub", "same bytes"), metadata: ImportMetadata(title: "One"))
        let again = try library.store.importFileReportingDuplicate(
            at: library.temp.file("b/renamed copy.epub", "same bytes"), metadata: ImportMetadata(title: "Another Title"))
        #expect(again.isDuplicate)
        #expect(again.entry.book.id == first.book.id)
        #expect(again.entry.book.title == "One")
        #expect(try library.store.allBooks().count == 1)
    }

    @Test func dedupeAlsoFindsBooksWrittenBeforeContentHashExisted() throws {
        let library = TestLibrary()
        var first = try library.add("Old Book", contents: "legacy bytes")
        first.book.contentHash = nil
        try library.store.save(first.book, in: first.folder)

        let again = try library.store.importFileReportingDuplicate(at: library.temp.file("again.epub", "legacy bytes"))
        #expect(again.isDuplicate)
        #expect(again.entry.book.id == first.book.id)
        // The hash is remembered so the next import does not hash the file again.
        #expect(try library.store.entry(id: first.book.id)?.book.contentHash == SHA256.hex(of: Data("legacy bytes".utf8)))
    }

    @Test func sameTitleDifferentContentGetsNumberedSlugs() throws {
        let library = TestLibrary()
        let slugs = try (1...3).map { try library.add("Dune", contents: "edition \($0)").folder.lastPathComponent }
        #expect(slugs == ["dune", "dune-2", "dune-3"])
        let entries = try library.store.allBooks()
        #expect(Set(entries.map(\.book.id)).count == 3)
        #expect(entries.map(\.book.fileName).sorted() == ["dune-2.epub", "dune-3.epub", "dune.epub"])
    }

    @Test func importRejectsUnsupportedAndMissingFiles() throws {
        let library = TestLibrary()
        #expect(throws: LibraryError.unsupportedFormat("txt")) {
            try library.store.importFile(at: library.temp.file("notes.txt", "x"), metadata: ImportMetadata())
        }
        let missing = library.temp.url.appendingPathComponent("missing.epub")
        #expect(throws: LibraryError.fileNotFound(missing.path)) {
            try library.store.importFile(at: missing, metadata: ImportMetadata())
        }
        #expect(throws: LibraryError.self) {
            try library.store.importFile(at: library.temp.url, metadata: ImportMetadata())
        }
        #expect(try library.store.allBooks().isEmpty)
    }

    @Test func bookJSONIsPrettySortedAndUsesISODates() throws {
        let library = TestLibrary()
        var entry = try library.add("Dated")
        entry.book.addedAt = date("2026-11-20T08:30:00Z")
        entry.book.finishedAt = date("2026-11-22T21:00:00Z")
        entry.book.sourceURL = "https://example.com/a/b"
        try library.store.save(entry.book, in: entry.folder)

        let text = try String(contentsOf: entry.metadataURL, encoding: .utf8)
        #expect(text.contains("\"addedAt\" : \"2026-11-20T08:30:00Z\""))
        #expect(text.contains("\"finishedAt\" : \"2026-11-22T21:00:00Z\""))
        #expect(text.contains("https://example.com/a/b"), "slashes are not escaped")
        let keys = text.split(separator: "\n").compactMap { line -> String? in
            guard line.hasPrefix("  \"") else { return nil }
            return String(line.dropFirst(3).prefix { $0 != "\"" })
        }
        #expect(keys == keys.sorted())
        #expect(try library.store.entry(id: entry.book.id)?.book == entry.book)
        #expect(try FileManager.default.contentsOfDirectory(atPath: entry.folder.path).sorted() == ["book.json", "dated.epub"])
    }

    @Test func decodingToleratesMissingAndUnknownFields() throws {
        let minimal = #"{"id": "b1", "fileName": "paper.pdf"}"#
        let book = try LibraryJSON.decoder().decode(Book.self, from: Data(minimal.utf8))
        #expect(book.title == "Untitled")
        #expect(book.format == .pdf)
        #expect(book.status == .toRead)
        #expect(book.authors.isEmpty && book.tags.isEmpty)
        #expect(book.contentHash == nil)

        let odd = """
            {"id": "b2", "fileName": "a.html", "title": "T", "format": "article", "status": "abandoned",
             "rating": "five", "addedAt": "2026-01-02T03:04:05.678+05:30", "futureField": {"x": 1}}
            """
        let tolerant = try LibraryJSON.decoder().decode(Book.self, from: Data(odd.utf8))
        #expect(tolerant.status == .toRead)
        #expect(tolerant.rating == nil)
        #expect(tolerant.kind == .article)
        #expect(abs(tolerant.addedAt.timeIntervalSince(date("2026-01-01T21:34:05Z")) - 0.678) < 0.001)

        #expect(throws: (any Error).self) {
            try LibraryJSON.decoder().decode(Book.self, from: Data(#"{"id": "b3", "fileName": "a.xyz"}"#.utf8))
        }
    }

    @Test func unreadableFoldersAreSkipped() throws {
        let library = TestLibrary()
        let good = try library.add("Good Book")
        let books = library.store.booksRoot
        _ = library.temp.file("Library/Books/broken/book.json", "{ this is not json")
        _ = library.temp.file("Library/Books/empty-folder/readme.txt", "no book.json here")
        _ = library.temp.file("Library/Books/stray-file.txt", "not a folder")
        _ = library.temp.file("Library/Books/.import-123/book.json", try String(contentsOf: good.metadataURL, encoding: .utf8))
        #expect(try FileManager.default.contentsOfDirectory(atPath: books.path).count == 5)
        #expect(try library.store.allBooks().map(\.book.id) == [good.book.id])
    }

    @Test func allBooksIsSortedByTitle() throws {
        let library = TestLibrary()
        for title in ["zebra", "Apple", "mango"] { try library.add(title) }
        #expect(try library.store.allBooks().map(\.book.title) == ["Apple", "mango", "zebra"])
    }

    @Test func setCoverWritesTheFileAndReplacesAnOlderCover() throws {
        let library = TestLibrary()
        let entry = try library.add("Covered")
        let first = try library.store.setCover(Data([1, 2, 3]), fileExtension: ".JPEG", generated: true, forBookID: entry.book.id)
        #expect(first.book.coverFile == "cover.jpg")
        #expect(first.book.coverIsGenerated)
        #expect(try Data(contentsOf: #require(first.coverURL)) == Data([1, 2, 3]))

        let second = try library.store.setCover(Data([9]), fileExtension: "png", generated: false, forBookID: entry.book.id)
        #expect(second.book.coverFile == "cover.png")
        #expect(!second.book.coverIsGenerated)
        #expect(!FileManager.default.fileExists(atPath: entry.folder.appendingPathComponent("cover.jpg").path))
        #expect(try library.store.entry(id: entry.book.id)?.book.coverFile == "cover.png")

        #expect(throws: LibraryError.bookNotFound("nope")) {
            try library.store.setCover(Data(), fileExtension: "png", generated: false, forBookID: "nope")
        }
    }

    @Test func deleteRemovesTheBookFolder() throws {
        let library = TestLibrary()
        let keep = try library.add("Keep")
        let drop = try library.add("Drop")
        // `toTrash: false` so the test never puts anything in the real Trash.
        try library.store.delete(id: drop.book.id, toTrash: false)
        #expect(!FileManager.default.fileExists(atPath: drop.folder.path))
        #expect(try library.store.allBooks().map(\.book.id) == [keep.book.id])
        #expect(throws: LibraryError.bookNotFound(drop.book.id)) {
            try library.store.delete(id: drop.book.id, toTrash: false)
        }
    }
}
