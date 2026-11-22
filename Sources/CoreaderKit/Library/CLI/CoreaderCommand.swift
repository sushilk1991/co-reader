import Foundation

/// The `coreader` command, as a value: arguments in, text and an exit code out. It lives
/// in CoreaderKit (not in the executable) so tests can run every command against a
/// temporary library without spawning a process. `Sources/coreader-cli/main.swift` only
/// wires it to the real library, stdout and `/usr/bin/open`.
public struct CoreaderCommand: Sendable {
    public struct Output: Sendable, Equatable {
        public var exitCode: Int32
        public var stdout: String
        public var stderr: String

        public init(exitCode: Int32 = 0, stdout: String = "", stderr: String = "") {
            self.exitCode = exitCode
            self.stdout = stdout
            self.stderr = stderr
        }
    }

    public var library: LibraryStore
    public var textStore: BookTextStore
    /// Styling (bold headings) is only used when stdout is a terminal.
    public var isTTY: Bool
    /// Time zone in which `--since YYYY-MM-DD` starts its day.
    public var timeZone: TimeZone
    /// Opens a `coreader://` link without bringing the app to the front.
    public var opener: @Sendable (URL) throws -> Void

    let notes = NotesStore()

    public init(
        library: LibraryStore,
        textStore: BookTextStore = BookTextStore(),
        isTTY: Bool = false,
        timeZone: TimeZone = .current,
        opener: @escaping @Sendable (URL) throws -> Void = { _ in throw Failure("Opening links is not available here.") }
    ) {
        self.library = library
        self.textStore = textStore
        self.isTTY = isTTY
        self.timeZone = timeZone
        self.opener = opener
    }

    /// A failure with the message to print. Exit code 2 means the command was used wrongly.
    public struct Failure: Error, LocalizedError, Equatable {
        public var message: String
        public var exitCode: Int32

        public init(_ message: String, exitCode: Int32 = 1) {
            self.message = message
            self.exitCode = exitCode
        }

        public var errorDescription: String? { message }

        static func usage(_ message: String, command: String? = nil) -> Failure {
            let hint = command.map { "coreader \($0) --help" } ?? "coreader --help"
            return Failure("\(message)\nSee `\(hint)`.", exitCode: 2)
        }
    }

    public func run(_ arguments: [String]) -> Output {
        var output = Output()
        do {
            guard let name = arguments.first else {
                output.stdout = Help.overview
                return output
            }
            let rest = Array(arguments.dropFirst())
            if ["help", "--help", "-h"].contains(name) {
                output.stdout = try rest.first.map { try Help.text(for: $0) } ?? Help.overview
                return output
            }
            guard Help.commands[name] != nil else {
                throw Failure.usage("Unknown command '\(name)'.")
            }
            if rest.contains("--help") || rest.contains("-h") {
                output.stdout = try Help.text(for: name)
                return output
            }
            switch name {
            case "path": try path(rest, &output)
            case "books": try books(rest, &output)
            case "notes": try notes(rest, &output)
            case "search": try search(rest, &output)
            case "export": try export(rest, &output)
            case "text": try text(rest, &output)
            case "add": try add(rest, &output)
            case "open": try open(rest, &output)
            default: throw Failure.usage("Unknown command '\(name)'.")
            }
        } catch let failure as Failure {
            output.stderr += "coreader: \(failure.message)\n"
            output.exitCode = failure.exitCode
        } catch {
            output.stderr += "coreader: \(error.localizedDescription)\n"
            output.exitCode = 1
        }
        return output
    }

    // MARK: - Commands

    private func path(_ args: [String], _ out: inout Output) throws {
        let parsed = try Arguments(args, command: "path", flags: ["--json"])
        try parsed.expectPositionals(0...0)
        if parsed.has("--json") {
            struct Info: Encodable { var libraryRoot: String; var exists: Bool; var textCache: String }
            out.stdout = try json(Info(
                libraryRoot: library.root.path,
                exists: FileManager.default.fileExists(atPath: library.root.path),
                textCache: textStore.cachesRoot.appendingPathComponent("text").path))
        } else {
            out.stdout = library.root.path + "\n"
        }
    }

    private func books(_ args: [String], _ out: inout Output) throws {
        let parsed = try Arguments(args, command: "books", flags: ["--json"], options: ["--status", "--min-rating"])
        try parsed.expectPositionals(0...0)
        var entries = try library.allBooks()
        if let text = parsed.value("--status") {
            guard let status = Self.status(text) else {
                throw Failure.usage("Unknown status '\(text)'. Use to-read, reading or read.", command: "books")
            }
            entries = entries.filter { $0.book.status == status }
        }
        if let text = parsed.value("--min-rating") {
            guard let minimum = Int(text), (1...5).contains(minimum) else {
                throw Failure.usage("--min-rating takes a number from 1 to 5.", command: "books")
            }
            entries = entries.filter { ($0.book.rating ?? 0) >= minimum }
        }
        let counts = entries.map { (try? notes.load($0).count) ?? 0 }
        if parsed.has("--json") {
            out.stdout = try json(zip(entries, counts).map { BookRecord($0, notes: $1) })
            return
        }
        guard !entries.isEmpty else {
            out.stderr = "No books match.\n"
            return
        }
        var lines = [bold("SLUG\tSTATUS\tRATING\tPROGRESS\tNOTES\tTITLE\tAUTHORS")]
        for (entry, count) in zip(entries, counts) {
            let book = entry.book
            lines.append([
                entry.folder.lastPathComponent,
                Self.statusName(book.status),
                book.rating.map(String.init) ?? "-",
                "\(Int((book.progress * 100).rounded()))%",
                String(count),
                Self.cell(book.title),
                Self.cell(book.authorLine),
            ].joined(separator: "\t"))
        }
        out.stdout = lines.joined(separator: "\n") + "\n"
    }

    private func notes(_ args: [String], _ out: inout Output) throws {
        let parsed = try Arguments(args, command: "notes", flags: ["--json"])
        try parsed.expectPositionals(1...Int.max, missing: "Which book? Give an id, a slug or part of a title.")
        let entry = try resolve(parsed.positionals.joined(separator: " "))
        if parsed.has("--json") {
            struct Payload: Encodable { var book: BookRecord; var annotations: [AnnotationRecord] }
            let annotations = try notes.load(entry)
            out.stdout = try json(Payload(
                book: BookRecord(entry, notes: annotations.count),
                annotations: annotations.map { AnnotationRecord($0, in: entry) }))
            return
        }
        guard FileManager.default.fileExists(atPath: entry.notesURL.path) else {
            out.stderr = "No notes yet for \"\(entry.book.title)\".\n"
            return
        }
        out.stdout = try String(contentsOf: entry.notesURL, encoding: .utf8)
    }

    private func search(_ args: [String], _ out: inout Output) throws {
        let parsed = try Arguments(args, command: "search", flags: ["--json"])
        try parsed.expectPositionals(1...Int.max, missing: "What should I search for?")
        let query = parsed.positionals.joined(separator: " ")
        let hits = try notes.search(query, in: library)
        if parsed.has("--json") {
            struct Hit: Encodable { var book: BookReference; var annotation: AnnotationRecord }
            out.stdout = try json(hits.map { Hit(book: BookReference($0.entry), annotation: AnnotationRecord($0.annotation, in: $0.entry)) })
            return
        }
        guard !hits.isEmpty else {
            out.stderr = "No notes match \"\(query)\".\n"
            return
        }
        var blocks: [String] = []
        for hit in hits {
            let annotation = hit.annotation
            var lines = [bold("\(Self.heading(for: hit.entry.book)) (\(NotesDocument.positionLabel(for: annotation.locator)))")]
            lines += NotesText.lines(annotation.quote).map { $0.isEmpty ? ">" : "> \($0)" }
            lines += NotesText.trimBlankLines(NotesText.lines(annotation.note))
            if !annotation.tags.isEmpty { lines.append("Tags: \(annotation.tags.joined(separator: ", "))") }
            lines.append(DeepLink.annotation(bookID: hit.entry.book.id, annotationID: annotation.id).url.absoluteString)
            blocks.append(lines.joined(separator: "\n"))
        }
        out.stdout = blocks.joined(separator: "\n\n") + "\n"
    }

    private func export(_ args: [String], _ out: inout Output) throws {
        let parsed = try Arguments(args, command: "export", options: ["--book", "--since"])
        try parsed.expectPositionals(0...0)
        var since: Date?
        if let text = parsed.value("--since") {
            guard let date = ISODate.day(text, in: timeZone) else {
                throw Failure.usage("--since takes a date like 2026-01-31.", command: "export")
            }
            since = date
        }
        let entries = try parsed.value("--book").map { [try resolve($0)] } ?? library.allBooks()

        var sections: [String] = []
        var total = 0
        for entry in entries {
            var annotations = (try? notes.load(entry)) ?? []
            if let since { annotations = annotations.filter { $0.createdAt >= since } }
            guard !annotations.isEmpty else { continue }
            total += annotations.count
            sections.append(Self.exportSection(entry, annotations))
        }
        guard !sections.isEmpty else {
            out.stderr = "No notes to export.\n"
            return
        }
        var header = "# Reading notes\n\n"
        header += "\(total) \(total == 1 ? "note" : "notes") from \(sections.count) \(sections.count == 1 ? "book" : "books")"
        if let text = parsed.value("--since") { header += ", written since \(text)" }
        header += ". Blockquotes are passages from the books; the text under them is the reader's own. Each link opens the passage in Coreader.\n"
        out.stdout = header + "\n" + sections.joined(separator: "\n")
    }

    private static func exportSection(_ entry: BookEntry, _ annotations: [Annotation]) -> String {
        let book = entry.book
        var lines = ["## \(NotesText.singleLine(book.title))", ""]
        var facts: [String] = []
        if !book.authors.isEmpty { facts.append("By \(book.authorLine)") }
        facts.append("Status: \(statusName(book.status))")
        if let rating = book.rating { facts.append("Rating: \(rating)/5") }
        facts.append("Book: \(DeepLink.book(id: book.id).url.absoluteString)")
        lines += [facts.joined(separator: " · "), ""]

        var previousChapter: String?
        for annotation in annotations {
            let chapter = NotesText.chapter(annotation.chapter)
            if let chapter, chapter != previousChapter { lines += ["### \(chapter)", ""] }
            previousChapter = chapter
            let quote = NotesText.lines(annotation.quote)
            if let asset = annotation.asset {
                let caption = NotesText.escapeBrackets(annotation.kind == .image ? annotation.quote : "")
                lines += ["![\(caption)](\(entry.assetsURL.appendingPathComponent(asset).absoluteString))", ""]
                if annotation.kind != .image || quote.count > 1 { lines += quote.map { $0.isEmpty ? ">" : "> \($0)" } + [""] }
            } else if !quote.isEmpty {
                lines += quote.map { $0.isEmpty ? ">" : "> \($0)" } + [""]
            }
            let note = NotesText.trimBlankLines(NotesText.lines(annotation.note))
            if !note.isEmpty { lines += note + [""] }
            if !annotation.tags.isEmpty { lines += ["Tags: \(annotation.tags.joined(separator: ", "))", ""] }
            let label = NotesText.escapeBrackets(NotesDocument.positionLabel(for: annotation.locator))
            lines += ["[\(label)](\(DeepLink.annotation(bookID: book.id, annotationID: annotation.id).url.absoluteString))", ""]
        }
        return lines.joined(separator: "\n")
    }

    private func text(_ args: [String], _ out: inout Output) throws {
        let parsed = try Arguments(args, command: "text", flags: ["--json", "--list"], options: ["--section"])
        try parsed.expectPositionals(1...Int.max, missing: "Which book? Give an id, a slug or part of a title.")
        let entry = try resolve(parsed.positionals.joined(separator: " "))
        let book = entry.book

        if !textStore.hasText(for: book.id) {
            // PDFs can be read right here; other formats are rendered by the app's web
            // reader, which is the only thing that can turn them into text.
            guard book.format == .pdf else {
                throw Failure("""
                    No extracted text for "\(book.title)" yet.
                    Open the book in Coreader once (`coreader open \(entry.folder.lastPathComponent)`); the app saves its text to \(textStore.folder(for: book.id).path), and this command will then print it.
                    The book file itself is at \(entry.fileURL.path).
                    """)
            }
            let sections = try textStore.extractPDF(at: entry.fileURL, book: book)
            try textStore.save(sections, for: book)
            out.stderr += "Extracted text from \(sections.count) PDF pages.\n"
        }

        let sections = try textStore.load(for: book.id)
        let files = try textStore.sectionFiles(for: book.id)
        var chosen = Array(sections.indices)
        if let value = parsed.value("--section") {
            guard let number = Int(value), sections.indices.contains(number - 1) else {
                throw Failure("\"\(book.title)\" has sections 1 to \(sections.count); there is no section \(value). List them with `coreader text \(entry.folder.lastPathComponent) --list`.")
            }
            chosen = [number - 1]
        }

        if parsed.has("--json") {
            struct Record: Encodable {
                var section: Int
                var title: String
                var characters: Int
                var file: String
                var link: String
                var text: String?
            }
            out.stdout = try json(chosen.map { n in
                Record(
                    section: n + 1, title: sections[n].title, characters: sections[n].text.count, file: files[n].path,
                    link: DeepLink.location(bookID: book.id, locator: sections[n].locator).url.absoluteString,
                    text: parsed.has("--list") ? nil : sections[n].text)
            })
        } else if parsed.has("--list") {
            var lines = [bold("SECTION\tCHARACTERS\tTITLE")]
            lines += chosen.map { "\($0 + 1)\t\(sections[$0].text.count)\t\(Self.cell(sections[$0].title))" }
            out.stdout = lines.joined(separator: "\n") + "\n"
        } else {
            out.stdout = chosen.map { n in
                let link = DeepLink.location(bookID: book.id, locator: sections[n].locator).url.absoluteString
                return "# \(NotesText.singleLine(sections[n].title))\n\n[Open in Coreader](\(link))\n\n\(sections[n].text)\n"
            }.joined(separator: "\n")
        }
    }

    private func add(_ args: [String], _ out: inout Output) throws {
        let parsed = try Arguments(args, command: "add", flags: ["--json"], options: ["--title", "--author", "--kind"])
        try parsed.expectPositionals(1...Int.max, missing: "Which file? Give one or more epub, pdf, mobi, azw3 or html files.")
        if parsed.value("--title") != nil, parsed.positionals.count > 1 {
            throw Failure.usage("--title only makes sense with a single file.", command: "add")
        }
        var kind: BookKind?
        if let text = parsed.value("--kind") {
            guard let known = BookKind(rawValue: text) else {
                throw Failure.usage("Unknown kind '\(text)'. Use book, paper or article.", command: "add")
            }
            kind = known
        }
        let authors = parsed.values("--author")
        let metadata = ImportMetadata(title: parsed.value("--title"), authors: authors.isEmpty ? nil : authors, kind: kind)

        struct Record: Encodable { var file: String; var added: Bool; var book: BookRecord? ; var error: String? }
        var records: [Record] = []
        var lines: [String] = []
        for path in parsed.positionals {
            let source = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
            do {
                let result = try library.importFileReportingDuplicate(at: source, metadata: metadata)
                let slug = result.entry.folder.lastPathComponent
                records.append(Record(file: path, added: !result.isDuplicate, book: BookRecord(result.entry, notes: nil), error: nil))
                lines.append("\(result.isDuplicate ? "exists" : "added")\t\(slug)\t\(Self.cell(result.entry.book.title))")
            } catch {
                records.append(Record(file: path, added: false, book: nil, error: error.localizedDescription))
                out.stderr += "coreader: \(path): \(error.localizedDescription)\n"
                out.exitCode = 1
            }
        }
        out.stdout = parsed.has("--json") ? try json(records) : lines.map { $0 + "\n" }.joined()
    }

    private func open(_ args: [String], _ out: inout Output) throws {
        let parsed = try Arguments(args, command: "open", options: ["--page"])
        try parsed.expectPositionals(1...Int.max, missing: "Which book? Give an id, a slug or part of a title.")
        let entry = try resolve(parsed.positionals.joined(separator: " "))
        var link = DeepLink.book(id: entry.book.id)
        if let text = parsed.value("--page") {
            guard let page = Int(text), page >= 1 else {
                throw Failure.usage("--page takes a page number, counted from 1.", command: "open")
            }
            link = .location(bookID: entry.book.id, locator: Locator(page: page - 1))
        }
        try opener(link.url)
        out.stdout = link.url.absoluteString + "\n"
    }

    // MARK: - Finding a book

    /// Exact id, then exact slug, then exact title, then a unique id prefix, then a
    /// title substring. Anything ambiguous is an error that lists the candidates.
    func resolve(_ reference: String) throws -> BookEntry {
        let entries = try library.allBooks()
        let wanted = NotesStore.fold(reference.trimmingCharacters(in: .whitespaces))
        guard !wanted.isEmpty else { throw Failure.usage("Which book? Give an id, a slug or part of a title.") }
        let tiers: [(BookEntry) -> Bool] = [
            { NotesStore.fold($0.book.id) == wanted },
            { NotesStore.fold($0.folder.lastPathComponent) == wanted },
            { NotesStore.fold($0.book.title) == wanted },
            { wanted.count >= 4 && NotesStore.fold($0.book.id).hasPrefix(wanted) },
            { NotesStore.fold($0.book.title).contains(wanted) || $0.folder.lastPathComponent.contains(wanted) },
        ]
        for tier in tiers {
            let matches = entries.filter(tier)
            if matches.count == 1 { return matches[0] }
            if matches.count > 1 {
                let list = matches.map { "  \($0.folder.lastPathComponent)\t\(Self.cell($0.book.title))" }.joined(separator: "\n")
                throw Failure("\"\(reference)\" matches \(matches.count) books. Use one of these slugs:\n\(list)")
            }
        }
        throw Failure("No book matches \"\(reference)\". List the library with `coreader books`.")
    }

    // MARK: - Output helpers

    private func bold(_ text: String) -> String {
        isTTY ? "\u{1B}[1m\(text)\u{1B}[0m" : text
    }

    private func json<T: Encodable>(_ value: T) throws -> String {
        String(decoding: try LibraryJSON.encoder().encode(value), as: UTF8.self) + "\n"
    }

    /// Tabs and newlines would break the one-row-per-book tables.
    static func cell(_ text: String) -> String {
        NotesText.singleLine(text).replacingOccurrences(of: "\t", with: " ")
    }

    static func heading(for book: Book) -> String {
        book.authors.isEmpty ? cell(book.title) : "\(cell(book.title)) — \(cell(book.authorLine))"
    }

    static func statusName(_ status: ReadingStatus) -> String {
        switch status {
        case .toRead: "to-read"
        case .reading: "reading"
        case .read: "read"
        }
    }

    static func status(_ text: String) -> ReadingStatus? {
        switch text.lowercased() {
        case "to-read", "toread", "to_read", "unread": .toRead
        case "reading": .reading
        case "read", "finished": .read
        default: nil
        }
    }
}

// MARK: - JSON shapes

/// A book as the CLI reports it: `book.json` vocabulary plus the paths and link an
/// agent needs next.
struct BookRecord: Encodable {
    var id: String
    var slug: String
    var title: String
    var authors: [String]
    var format: BookFormat
    var kind: BookKind
    var status: ReadingStatus
    var rating: Int?
    var progress: Double
    var tags: [String]
    var addedAt: Date
    var finishedAt: Date?
    var folder: String
    var file: String
    var notesFile: String
    var notes: Int?
    var link: String

    init(_ entry: BookEntry, notes: Int?) {
        let book = entry.book
        id = book.id
        slug = entry.folder.lastPathComponent
        title = book.title
        authors = book.authors
        format = book.format
        kind = book.kind
        status = book.status
        rating = book.rating
        progress = book.progress
        tags = book.tags
        addedAt = book.addedAt
        finishedAt = book.finishedAt
        folder = entry.folder.path
        file = entry.fileURL.path
        notesFile = entry.notesURL.path
        self.notes = notes
        link = DeepLink.book(id: book.id).url.absoluteString
    }
}

struct BookReference: Encodable {
    var id: String
    var slug: String
    var title: String
    var authors: [String]

    init(_ entry: BookEntry) {
        id = entry.book.id
        slug = entry.folder.lastPathComponent
        title = entry.book.title
        authors = entry.book.authors
    }
}

struct AnnotationRecord: Encodable {
    var id: String
    var kind: AnnotationKind
    var color: HighlightColor
    var quote: String
    var note: String
    var chapter: String?
    var tags: [String]
    var createdAt: Date
    var position: String
    var locator: Locator
    /// Absolute path of the saved image, when there is one.
    var asset: String?
    var link: String

    init(_ annotation: Annotation, in entry: BookEntry) {
        id = annotation.id
        kind = annotation.kind
        color = annotation.color
        quote = annotation.quote
        note = annotation.note
        chapter = annotation.chapter
        tags = annotation.tags
        createdAt = annotation.createdAt
        position = NotesDocument.positionLabel(for: annotation.locator)
        locator = annotation.locator
        asset = annotation.asset.map { entry.assetsURL.appendingPathComponent($0).path }
        link = DeepLink.annotation(bookID: entry.book.id, annotationID: annotation.id).url.absoluteString
    }
}
