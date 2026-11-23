import Foundation

/// A book's `notes.md`, parsed. The Markdown file is the only stored copy of the notes,
/// so this type has two jobs: lose nothing the app wrote, and lose nothing a person
/// typed into the file by hand.
///
/// File shape (see `LibraryReadme` for the version agents read):
///
///     ---
///     title: "…"            front matter: title, author, coreader_id, source, updated,
///     ---                   then any keys the user added (kept verbatim)
///
///     # Title
///
///     user text             → `preamble`
///
///     ## Chapter            written above the first block of each chapter
///
///     <!-- coreader {…} --> one line of compact JSON: everything except quote and note
///     > quote               blockquote directly under the comment
///
///     ![caption](assets/x)  when the annotation has an asset
///
///     note paragraphs       any Markdown
///
///     [p. 42](coreader://open?book=…&a=…)   ends the block
///
///     user text             → `interleaved[<id of the block above>]`
///
///     user text after the last block → `trailer`
///
/// Sources of truth when parsing: the Markdown for `quote` and `note` (so edits made in
/// any editor win), a `## heading` directly above a block for `chapter` (so renaming a
/// heading renames the chapter), the comment for everything else.
///
/// Text is normalised on the way out: line endings become `\n`, blank lines around a
/// note are dropped, and dates are kept to the second.
public struct NotesDocument: Sendable, Equatable {
    public var bookID: String
    public var title: String
    public var authors: [String]
    public var annotations: [Annotation]
    /// Written to the front matter as `updated`. `NotesStore` sets it on every write.
    public var updated: Date?
    /// The user's own text between the title and the first annotation.
    public var preamble: String
    /// The user's own text after the last annotation, e.g. a `## My summary` section.
    public var trailer: String
    /// The user's own text that follows a given annotation, keyed by annotation id.
    public var interleaved: [String: String]
    /// Front matter lines Coreader does not own (Obsidian `tags:`, `aliases:` …), verbatim.
    public var extraFrontMatter: [String]

    public init(
        bookID: String,
        title: String,
        authors: [String] = [],
        annotations: [Annotation] = [],
        updated: Date? = nil,
        preamble: String = "",
        trailer: String = "",
        interleaved: [String: String] = [:],
        extraFrontMatter: [String] = []
    ) {
        self.bookID = bookID
        self.title = title
        self.authors = authors
        self.annotations = annotations
        self.updated = updated
        self.preamble = preamble
        self.trailer = trailer
        self.interleaved = interleaved
        self.extraFrontMatter = extraFrontMatter
    }

    /// Reading order: position in the book, then creation time. The sort is stable, so
    /// annotations that tie keep the order they had.
    public static func readingOrder(_ annotations: [Annotation]) -> [Annotation] {
        annotations.enumerated().sorted { l, r in
            if l.element.locator.fraction != r.element.locator.fraction {
                return l.element.locator.fraction < r.element.locator.fraction
            }
            if l.element.createdAt != r.element.createdAt { return l.element.createdAt < r.element.createdAt }
            return l.offset < r.offset
        }.map(\.element)
    }

    /// "p. 42" when the locator has a label or a page, otherwise a percentage.
    public static func positionLabel(for locator: Locator) -> String {
        if let label = locator.label.map(NotesText.singleLine), !label.isEmpty { return label }
        if let page = locator.page { return "p. \(page + 1)" }
        return "\(Int((min(max(locator.fraction, 0), 1) * 100).rounded()))%"
    }

    // MARK: - Writing

    public func markdown() -> String {
        var out: [String] = ["---", "title: \(NotesText.yamlQuoted(title))"]
        if authors.isEmpty {
            out.append("author: []")
        } else {
            out.append("author:")
            out += authors.map { "  - \(NotesText.yamlQuoted($0))" }
        }
        out.append("coreader_id: \(NotesText.yamlPlainOrQuoted(bookID))")
        out.append("source: coreader")
        if let updated { out.append("updated: \(ISODate.string(updated))") }
        out += extraFrontMatter
        out += ["---", "", "# \(NotesText.singleLine(title))"]

        func appendText(_ text: String?) {
            let lines = NotesText.trimBlankLines(NotesText.lines(text ?? ""))
            guard !lines.isEmpty else { return }
            out.append("")
            out += lines
        }

        appendText(preamble)
        var previousChapter: String?
        var written = Set<String>()
        for (n, annotation) in Self.readingOrder(annotations).enumerated() {
            let chapter = NotesText.chapter(annotation.chapter)
            if let chapter, n == 0 || chapter != previousChapter {
                out += ["", "## \(chapter)"]
            }
            previousChapter = chapter
            out.append("")
            out += Self.block(for: annotation, bookID: bookID)
            if written.insert(annotation.id).inserted { appendText(interleaved[annotation.id]) }
        }
        // Text that followed an annotation which no longer exists must not vanish.
        for id in interleaved.keys.sorted() where !written.contains(id) { appendText(interleaved[id]) }
        appendText(trailer)
        return out.joined(separator: "\n") + "\n"
    }

    static func block(for annotation: Annotation, bookID: String) -> [String] {
        var lines = [NotesMachineLine.render(annotation)]
        let quoteLines = NotesText.lines(annotation.quote)
        // An image's one-line caption lives in the alt text; anything longer needs a blockquote.
        let captionInAlt = annotation.asset != nil && annotation.kind == .image && quoteLines.count <= 1
        if !quoteLines.isEmpty, !captionInAlt {
            lines += quoteLines.map { $0.isEmpty ? ">" : "> \($0)" }
        }
        if let asset = annotation.asset {
            if lines.count > 1 { lines.append("") }
            let alt = captionInAlt ? NotesText.escapeBrackets(annotation.quote) : ""
            lines.append("![\(alt)](assets/\(NotesText.encodePath(asset)))")
        }
        let note = NotesText.trimBlankLines(NotesText.lines(annotation.note))
        if !note.isEmpty {
            lines.append("")
            lines += note.map { NotesText.escapeNoteLine($0, annotationID: annotation.id) }
        } else if lines.count == 1 {
            // Keeps the "quote sits directly under the comment" rule unambiguous.
            lines.append("")
        }
        if lines.last != "" { lines.append("") }
        let label = NotesText.escapeBrackets(positionLabel(for: annotation.locator))
        let link = DeepLink.annotation(bookID: bookID, annotationID: annotation.id).url.absoluteString
        lines.append("[\(label)](\(link))")
        return lines
    }

    // MARK: - Reading

    public static func parse(_ markdown: String) -> NotesDocument {
        var document = NotesDocument(bookID: "", title: "")
        var text = NotesText.normalizeNewlines(markdown)
        if text.hasPrefix("\u{FEFF}") { text.removeFirst() }
        let allLines = text.components(separatedBy: "\n")

        var body = allLines[...]
        if allLines.first.map(NotesText.trimTrailing) == "---",
           let end = allLines.dropFirst().firstIndex(where: { ["---", "..."].contains(NotesText.trimTrailing($0)) }) {
            NotesFrontMatter.parse(Array(allLines[1..<end]), into: &document)
            body = allLines[(end + 1)...]
        }

        // Split the body at the machine lines. A comment whose JSON does not parse is not
        // a block start: it stays in the surrounding text, so nothing is thrown away.
        var head: [String] = []
        var blocks: [(machine: NotesMachineLine, lines: [String])] = []
        for line in body {
            if let machine = NotesMachineLine(line: line) {
                blocks.append((machine, []))
            } else if blocks.isEmpty {
                head.append(line)
            } else {
                blocks[blocks.count - 1].lines.append(line)
            }
        }

        head = NotesText.trimBlankLines(head)
        if let first = head.first, first.hasPrefix("# ") {
            let heading = first.dropFirst(2).trimmingCharacters(in: .whitespaces)
            if document.title.isEmpty {
                document.title = heading
                head.removeFirst()
            } else if heading == NotesText.singleLine(document.title) {
                head.removeFirst()
            }
        }

        var gap = head // text between the previous block (or the title) and the next block
        var previousID: String?
        var rename: (from: String, to: String)?
        for (n, block) in blocks.enumerated() {
            let machine = block.machine
            let lines = block.lines
            var index = 0

            var quoteLines: [String] = []
            while index < lines.count, lines[index].hasPrefix(">") {
                var line = lines[index].dropFirst()
                if line.hasPrefix(" ") { line = line.dropFirst() }
                quoteLines.append(String(line))
                index += 1
            }
            func skipBlank() { while index < lines.count, NotesText.isBlank(lines[index]) { index += 1 } }
            skipBlank()
            var alt: String?
            if machine.asset != nil, index < lines.count, let found = NotesText.imageAlt(lines[index]) {
                alt = found
                index += 1
                skipBlank()
            }

            var noteLines = Array(lines[index...])
            var after: [String] = []
            if let end = noteLines.firstIndex(where: { NotesText.isLinkLine($0, annotationID: machine.id) }) {
                after = Array(noteLines[(end + 1)...])
                noteLines = Array(noteLines[..<end])
            } else if n < blocks.count - 1 {
                // The link line was deleted. The next block's chapter heading would
                // otherwise be swallowed by this note.
                noteLines = NotesText.trimBlankLines(noteLines)
                if let last = noteLines.last, NotesText.chapterHeading(last) != nil {
                    after = [last]
                    noteLines.removeLast()
                }
            }
            let note = NotesText.trimBlankLines(noteLines)
                .map { NotesText.unescapeNoteLine($0, annotationID: machine.id) }
                .joined(separator: "\n")

            // The gap above this block: user text, then possibly this block's chapter heading.
            var gapLines = NotesText.trimBlankLines(gap)
            var heading: String?
            if let last = gapLines.last, let found = NotesText.chapterHeading(last) {
                heading = found
                gapLines = NotesText.trimBlankLines(Array(gapLines.dropLast()))
            }
            document.keep(gapLines, after: previousID)

            var chapter = NotesText.chapter(machine.chapter)
            if let heading {
                // A renamed heading renames the chapter for every block it used to cover.
                if let chapter, chapter != heading { rename = (chapter, heading) } else { rename = nil }
                chapter = heading
            } else if let active = rename, chapter == active.from {
                chapter = active.to
            } else {
                rename = nil
            }

            document.annotations.append(Annotation(
                id: machine.id,
                kind: machine.kind,
                quote: quoteLines.isEmpty ? (alt ?? "") : quoteLines.joined(separator: "\n"),
                note: note,
                color: machine.color,
                locator: machine.locator,
                chapter: chapter,
                asset: machine.asset,
                tags: machine.tags,
                createdAt: machine.createdAt
            ))
            gap = after
            previousID = machine.id
        }

        let rest = NotesText.trimBlankLines(gap).joined(separator: "\n")
        if blocks.isEmpty { document.preamble = rest } else { document.trailer = rest }
        return document
    }

    private mutating func keep(_ lines: [String], after annotationID: String?) {
        guard !lines.isEmpty else { return }
        let text = lines.joined(separator: "\n")
        guard let annotationID else {
            preamble = text
            return
        }
        interleaved[annotationID] = interleaved[annotationID].map { $0 + "\n\n" + text } ?? text
    }
}

/// The `<!-- coreader {...} -->` line: compact JSON with a fixed key order.
struct NotesMachineLine {
    var id: String
    var kind: AnnotationKind
    var color: HighlightColor
    var locator: Locator
    var chapter: String?
    var createdAt: Date
    var tags: [String]
    var asset: String?

    static let prefix = "<!-- coreader"

    static func render(_ annotation: Annotation) -> String {
        let encoder = LibraryJSON.encoder(pretty: false)
        func json<T: Encodable>(_ value: T) -> String {
            (try? encoder.encode(value)).map { String(decoding: $0, as: UTF8.self) } ?? "null"
        }
        var fields = [
            "\"id\":\(json(annotation.id))",
            "\"kind\":\(json(annotation.kind))",
            "\"color\":\(json(annotation.color))",
            "\"locator\":\(json(annotation.locator))",
        ]
        if let chapter = NotesText.chapter(annotation.chapter) { fields.append("\"chapter\":\(json(chapter))") }
        fields.append("\"createdAt\":\(json(annotation.createdAt))")
        if !annotation.tags.isEmpty { fields.append("\"tags\":\(json(annotation.tags))") }
        if let asset = annotation.asset { fields.append("\"asset\":\(json(asset))") }
        // `-->` inside a string would end the HTML comment early. `>` is the same
        // character to every JSON parser and harmless to every Markdown renderer.
        let body = "{\(fields.joined(separator: ","))}"
            .replacingOccurrences(of: ">", with: "\\u003e")
            .replacingOccurrences(of: "<", with: "\\u003c")
        return "\(prefix) \(body) -->"
    }

    /// Nil unless the line is a well-formed machine line with an id. Everything else is
    /// optional, so a person or agent can add a note with just `{"id":"…"}`.
    init?(line: String) {
        let line = NotesText.trimTrailing(line)
        guard line.hasPrefix(Self.prefix + " "), line.hasSuffix("-->") else { return nil }
        let json = line.dropFirst(Self.prefix.count).dropLast(3).trimmingCharacters(in: .whitespaces)
        guard let raw = try? JSONDecoder().decode(Raw.self, from: Data(json.utf8)), !raw.id.isEmpty else { return nil }
        id = raw.id
        kind = raw.kind.flatMap(AnnotationKind.init(rawValue:)) ?? (raw.asset != nil ? .image : .highlight)
        color = raw.color.flatMap(HighlightColor.init(rawValue:)) ?? .yellow
        locator = Locator(
            cfi: raw.locator?.cfi, page: raw.locator?.page, rects: raw.locator?.rects,
            fraction: raw.locator?.fraction ?? 0, label: raw.locator?.label)
        chapter = raw.chapter
        createdAt = raw.createdAt.flatMap(ISODate.parse) ?? Date(timeIntervalSince1970: 0)
        tags = raw.tags ?? []
        asset = raw.asset
    }

    private struct Raw: Decodable {
        struct RawLocator: Decodable {
            var cfi: String?
            var page: Int?
            var rects: [[Double]]?
            var fraction: Double?
            var label: String?
        }
        var id: String
        var kind: String?
        var color: String?
        var locator: RawLocator?
        var chapter: String?
        var createdAt: String?
        var tags: [String]?
        var asset: String?
    }
}

/// Line-level helpers shared by the writer and the parser.
enum NotesText {
    static func normalizeNewlines(_ text: String) -> String {
        text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
    }

    /// Lines of a text; an empty text has no lines.
    static func lines(_ text: String) -> [String] {
        text.isEmpty ? [] : normalizeNewlines(text).components(separatedBy: "\n")
    }

    static func isBlank(_ line: String) -> Bool {
        line.allSatisfy { $0 == " " || $0 == "\t" }
    }

    static func trimTrailing(_ line: String) -> String {
        var line = Substring(line)
        while let last = line.last, last == " " || last == "\t" { line.removeLast() }
        return String(line)
    }

    static func trimBlankLines(_ lines: [String]) -> [String] {
        var slice = lines[...]
        while let first = slice.first, isBlank(first) { slice.removeFirst() }
        while let last = slice.last, isBlank(last) { slice.removeLast() }
        return Array(slice)
    }

    static func singleLine(_ text: String) -> String {
        normalizeNewlines(text).split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }.joined(separator: " ")
    }

    /// A chapter title as it can appear in a `## ` heading: one line, or nil when empty.
    static func chapter(_ text: String?) -> String? {
        text.map(singleLine)?.nonEmpty
    }

    static func chapterHeading(_ line: String) -> String? {
        guard line.hasPrefix("## ") else { return nil }
        return chapter(String(line.dropFirst(3)))
    }

    // Square brackets in a link label or image caption.

    static func escapeBrackets(_ text: String) -> String {
        var out = ""
        for character in singleLine(text) {
            if character == "\\" || character == "[" || character == "]" { out.append("\\") }
            out.append(character)
        }
        return out
    }

    static func unescapeBrackets(_ text: String) -> String {
        var out = ""
        var escaped = false
        for character in text {
            if escaped {
                if !(character == "\\" || character == "[" || character == "]") { out.append("\\") }
                out.append(character)
                escaped = false
            } else if character == "\\" {
                escaped = true
            } else {
                out.append(character)
            }
        }
        if escaped { out.append("\\") }
        return out
    }

    static func encodePath(_ fileName: String) -> String {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "()")
        return fileName.addingPercentEncoding(withAllowedCharacters: allowed) ?? fileName
    }

    /// The caption of a line that is only `![caption](target)`.
    static func imageAlt(_ line: String) -> String? {
        let line = trimTrailing(line)
        guard line.hasPrefix("!["), line.hasSuffix(")"), let close = line.range(of: "](", options: .backwards) else { return nil }
        return unescapeBrackets(String(line[line.index(line.startIndex, offsetBy: 2)..<close.lowerBound]))
    }

    /// True for the line that ends a block: `[label](coreader://open?book=…&a=<id>)`.
    static func isLinkLine(_ line: String, annotationID: String) -> Bool {
        let line = trimTrailing(line)
        guard line.hasPrefix("["), line.hasSuffix(")"), let open = line.range(of: "](", options: .backwards),
              let url = URL(string: String(line[open.upperBound...].dropLast())),
              case .annotation(_, let id)? = DeepLink(url: url) else { return false }
        return id == annotationID
    }

    // A note may itself contain a line that looks like a machine line or like its own
    // closing link. Such lines get one leading backslash on the way out (Markdown shows
    // them unchanged) and lose one on the way in.

    private static func needsEscape(_ line: Substring, annotationID: String) -> Bool {
        let bare = line.drop { $0 == "\\" }
        return bare.hasPrefix(NotesMachineLine.prefix) || isLinkLine(String(bare), annotationID: annotationID)
    }

    static func escapeNoteLine(_ line: String, annotationID: String) -> String {
        needsEscape(line[...], annotationID: annotationID) ? "\\" + line : line
    }

    static func unescapeNoteLine(_ line: String, annotationID: String) -> String {
        line.hasPrefix("\\") && needsEscape(line[...], annotationID: annotationID) ? String(line.dropFirst()) : line
    }

    // YAML scalars. Titles are always double-quoted, which is valid for any text.

    static func yamlQuoted(_ text: String) -> String {
        var out = "\""
        for character in normalizeNewlines(text) {
            switch character {
            case "\\": out += "\\\\"
            case "\"": out += "\\\""
            case "\n": out += "\\n"
            case "\t": out += "\\t"
            default: out.append(character)
            }
        }
        return out + "\""
    }

    static func yamlPlainOrQuoted(_ text: String) -> String {
        let plain = !text.isEmpty && text.unicodeScalars.allSatisfy {
            ("a"..."z").contains($0) || ("A"..."Z").contains($0) || ("0"..."9").contains($0) || $0 == "-" || $0 == "_" || $0 == "."
        }
        // An id of only digits would be read back as a number by other YAML tools.
        return plain && !text.unicodeScalars.allSatisfy({ ("0"..."9").contains($0) || $0 == "." }) ? text : yamlQuoted(text)
    }
}
