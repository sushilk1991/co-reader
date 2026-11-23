import Foundation
import Testing
@testable import CoreaderKit

private let bookID = "0b54c1de-6f0a-4a43-9a51-0a3c8a3a8f0e"

private func highlight(
    _ id: String, at fraction: Double, quote: String = "A passage.", note: String = "", chapter: String? = nil,
    page: Int? = nil, created: String = "2026-11-20T08:00:00Z", tags: [String] = []
) -> Annotation {
    Annotation(
        id: id, kind: .highlight, quote: quote, note: note, color: .yellow,
        locator: Locator(page: page, fraction: fraction, label: page.map { "p. \($0 + 1)" }),
        chapter: chapter, tags: tags, createdAt: date(created))
}

private func document(_ annotations: [Annotation]) -> NotesDocument {
    NotesDocument(
        bookID: bookID, title: "Thinking, Fast and Slow", authors: ["Daniel Kahneman"],
        annotations: annotations, updated: date("2026-11-23T10:15:30Z"))
}

/// One annotation through Markdown and back.
private func roundTrip(_ annotation: Annotation) -> Annotation? {
    let parsed = NotesDocument.parse(document([annotation]).markdown())
    #expect(parsed.annotations.count == 1)
    #expect(parsed.preamble.isEmpty && parsed.trailer.isEmpty && parsed.interleaved.isEmpty)
    return parsed.annotations.first
}

@Suite struct NotesDocumentFormatTests {
    @Test func writesTheDocumentedShape() {
        let doc = document([
            highlight(
                "a1b2c3d4e5f6", at: 0.08, quote: "System 1 operates automatically and quickly,\nwith little or no effort.",
                note: "This is the *whole* book in one line.\n\nSecond paragraph.", chapter: "The Characters of the Story",
                page: 20, tags: ["attention"]),
            Annotation(
                id: "bbbbbbbbbbbb", kind: .note, note: "A free-standing thought.", color: .blue,
                locator: Locator(cfi: "epubcfi(/6/4!/4/2)", fraction: 0.5), chapter: "Part Two",
                createdAt: date("2026-11-21T09:00:00Z")),
            Annotation(
                id: "cccccccccccc", kind: .image, quote: "Figure 3: the Müller-Lyer illusion", note: "Still fools me.",
                color: .green, locator: Locator(page: 26, fraction: 0.5, label: "p. 27"), chapter: "Part Two",
                asset: "figure 3.png", createdAt: date("2026-11-21T09:05:00Z")),
        ])
        let expected = """
            ---
            title: "Thinking, Fast and Slow"
            author:
              - "Daniel Kahneman"
            coreader_id: 0b54c1de-6f0a-4a43-9a51-0a3c8a3a8f0e
            source: coreader
            updated: 2026-11-23T10:15:30Z
            ---

            # Thinking, Fast and Slow

            ## The Characters of the Story

            <!-- coreader {"id":"a1b2c3d4e5f6","kind":"highlight","color":"yellow","locator":{"fraction":0.08,"label":"p. 21","page":20},"chapter":"The Characters of the Story","createdAt":"2026-11-20T08:00:00Z","tags":["attention"]} -->
            > System 1 operates automatically and quickly,
            > with little or no effort.

            This is the *whole* book in one line.

            Second paragraph.

            [p. 21](coreader://open?book=0b54c1de-6f0a-4a43-9a51-0a3c8a3a8f0e&a=a1b2c3d4e5f6)

            ## Part Two

            <!-- coreader {"id":"bbbbbbbbbbbb","kind":"note","color":"blue","locator":{"cfi":"epubcfi(/6/4!/4/2)","fraction":0.5},"chapter":"Part Two","createdAt":"2026-11-21T09:00:00Z"} -->

            A free-standing thought.

            [50%](coreader://open?book=0b54c1de-6f0a-4a43-9a51-0a3c8a3a8f0e&a=bbbbbbbbbbbb)

            <!-- coreader {"id":"cccccccccccc","kind":"image","color":"green","locator":{"fraction":0.5,"label":"p. 27","page":26},"chapter":"Part Two","createdAt":"2026-11-21T09:05:00Z","asset":"figure 3.png"} -->
            ![Figure 3: the Müller-Lyer illusion](assets/figure%203.png)

            Still fools me.

            [p. 27](coreader://open?book=0b54c1de-6f0a-4a43-9a51-0a3c8a3a8f0e&a=cccccccccccc)

            """
        #expect(doc.markdown() == expected)
        #expect(NotesDocument.parse(expected) == doc)
    }

    @Test func sortsByPositionThenCreationTime() {
        let doc = document([
            highlight("late", at: 0.9),
            highlight("tie-second", at: 0.3, created: "2026-11-20T09:00:00Z"),
            highlight("early", at: 0.1),
            highlight("tie-first", at: 0.3, created: "2026-11-20T08:00:00Z"),
            highlight("tie-third", at: 0.3, created: "2026-11-20T09:00:00Z"),
        ])
        #expect(NotesDocument.parse(doc.markdown()).annotations.map(\.id) == ["early", "tie-first", "tie-second", "tie-third", "late"])
    }

    @Test func chapterHeadingsAppearOncePerRunAndChaptersRoundTrip() {
        let annotations = [
            highlight("a", at: 0.1, chapter: "One"),
            highlight("b", at: 0.2, chapter: "One"),
            highlight("c", at: 0.3, chapter: nil),
            highlight("d", at: 0.4, chapter: "One"),
            highlight("e", at: 0.5, chapter: " Two: The Sequel\n"),
        ]
        let markdown = document(annotations).markdown()
        let headings = markdown.split(separator: "\n").filter { $0.hasPrefix("## ") }
        #expect(headings == ["## One", "## One", "## Two: The Sequel"])
        #expect(NotesDocument.parse(markdown).annotations.map(\.chapter) == ["One", "One", nil, "One", "Two: The Sequel"])
    }

    @Test func emptyDocumentRoundTrips() {
        let doc = NotesDocument(bookID: bookID, title: "Empty: \"quoted\" \\ title", authors: [])
        let markdown = doc.markdown()
        #expect(markdown.contains("author: []"))
        #expect(!markdown.contains("updated:"))
        #expect(NotesDocument.parse(markdown) == doc)
    }

    @Test func frontMatterEscapingRoundTrips() {
        var doc = document([])
        doc.title = "He said \"hi\": a #story\\ with 'quotes'"
        doc.authors = ["O'Brien, Flann", "Name \"Nick\" Surname", "plain"]
        doc.bookID = "12345"
        let parsed = NotesDocument.parse(doc.markdown())
        #expect(parsed.title == doc.title)
        #expect(parsed.authors == doc.authors)
        #expect(parsed.bookID == "12345")
        #expect(doc.markdown().contains("coreader_id: \"12345\""), "an all-digit id must stay a string for other YAML readers")
        #expect(parsed.updated == doc.updated)
    }
}

@Suite struct NotesDocumentRoundTripTests {
    @Test func everyFieldSurvives() {
        let annotation = Annotation(
            id: "f00dfacecafe", kind: .highlight, quote: "Quoted.", note: "Noted.", color: .purple,
            locator: Locator(
                cfi: "epubcfi(/6/14[chap05]!/4/2/1:0,/1:42)", page: 41, rects: [[72.5, 600, 300.25, 14], [72.5, 584, 120, 14]],
                fraction: 0.123456789012345, label: "p. 42"),
            chapter: "Chapter 5", asset: nil, tags: ["bias", "two words", "c++"],
            createdAt: date("2024-02-29T23:59:59Z"))
        #expect(roundTrip(annotation) == annotation)
    }

    @Test(arguments: AnnotationKind.allKinds, HighlightColor.allCases)
    func kindsAndColors(kind: AnnotationKind, color: HighlightColor) {
        let annotation = Annotation(
            id: "abc123abc123", kind: kind, quote: "q", note: "n", color: color,
            locator: Locator(fraction: 0.5), createdAt: date("2026-01-01T00:00:00Z"))
        #expect(roundTrip(annotation) == annotation)
    }

    @Test(arguments: [
        "Line one\nline two\nline three",
        "Paragraph one.\n\nParagraph two after a blank line.",
        "> already a blockquote\n>> nested",
        "a > b and b --> c, then <!-- not a comment -->",
        "ends the comment early? -->",
        "`inline code` and ```fenced``` and a ` stray backtick",
        "    indented like code\n\tand a tab",
        "trailing spaces   \nand more  ",
        "# looks like a heading\n## and another\n- and a list",
        "<!-- coreader {\"id\":\"fake\"} -->",
        "[p. 1](coreader://open?book=x&a=abc123abc123)",
        "![alt](assets/x.png)",
        "---\ntitle: fake front matter\n---",
        "unicode: “curly” — naïve café 日本語 🎉",
        "trailing newline\n",
        "\nleading newline",
        " ",
    ])
    func nastyQuotes(quote: String) {
        let annotation = highlight("abc123abc123", at: 0.4, quote: quote, note: "My note.")
        #expect(roundTrip(annotation) == annotation)
    }

    @Test(arguments: [
        "Para one.\n\nPara two.\n\n\nPara three after two blank lines.",
        "# A heading in my note\n\n## A second-level heading\n\nText.",
        "- item one\n- item two\n  - nested\n\n1. numbered\n2. list",
        "> I am quoting someone else in my note\n\nand then replying.",
        "```swift\nlet x = 1 // code with <!-- and --> inside\n```",
        "a --> b, x > y, `<!--`",
        "<!-- coreader {\"id\":\"fake000000000\",\"kind\":\"note\"} -->\nthat looked like a block start",
        "\\<!-- coreader already escaped once",
        "[p. 1](coreader://open?book=whatever&a=abc123abc123)\nthat looked like my own closing link",
        "\\[p. 1](coreader://open?book=whatever&a=abc123abc123)",
        "[a link to another note](coreader://open?book=whatever&a=other0000000)",
        "![an image in my note](assets/other.png)\n\ntext",
        "    starts with indented code",
        "---\n\nthematic breaks\n\n---",
        "| a | b |\n|---|---|\n| 1 | 2 |",
        "line with trailing spaces  \nhard break",
    ])
    func nastyNotes(note: String) {
        for quote in ["A passage.", ""] {
            let annotation = highlight("abc123abc123", at: 0.4, quote: quote, note: note, chapter: "Ch")
            #expect(roundTrip(annotation) == annotation, "quote: \(quote.debugDescription)")
        }
    }

    @Test func nastyNotesDoNotLeakIntoNeighbours() {
        let nasty = "## Looks like a chapter\n\n<!-- coreader {\"id\":\"zzz\"} -->\n> fake quote\n\n[x](coreader://open?book=b&a=first0000000)"
        let annotations = [
            highlight("first0000000", at: 0.1, quote: "One", note: nasty, chapter: "A"),
            highlight("second000000", at: 0.2, quote: "Two", note: "plain", chapter: "A"),
            highlight("third0000000", at: 0.3, quote: "Three", note: "", chapter: "B"),
        ]
        let parsed = NotesDocument.parse(document(annotations).markdown())
        #expect(parsed.annotations == annotations)
        #expect(parsed.interleaved.isEmpty && parsed.trailer.isEmpty)
    }

    @Test func imagesRoundTrip() {
        func image(_ quote: String, note: String = "", kind: AnnotationKind = .image, asset: String = "snip-2.png") -> Annotation {
            Annotation(
                id: "abc123abc123", kind: kind, quote: quote, note: note, color: .yellow,
                locator: Locator(page: 3, fraction: 0.2), asset: asset, createdAt: date("2026-01-01T00:00:00Z"))
        }
        let cases = [
            image(""),
            image("A caption"),
            image("Caption with [brackets], a \\ backslash and (parens)"),
            image("A caption\nover two lines", note: "note"),
            image("", note: "![looks like an image](assets/other.png)"),
            image("Highlighted text that also has a snapshot", note: "n", kind: .highlight),
            image("", note: "> a note that starts with a blockquote", kind: .highlight),
            image("caption", asset: "weird name (1) [x].png"),
        ]
        for annotation in cases {
            #expect(roundTrip(annotation) == annotation, "\(annotation.quote.debugDescription) / \(annotation.note.debugDescription)")
        }
        let markdown = document([image("A caption")]).markdown()
        #expect(markdown.contains("\n![A caption](assets/snip-2.png)\n"))
        #expect(!markdown.contains("> A caption"), "a one-line caption is not repeated as a blockquote")
    }

    @Test func metadataThatWouldBreakTheCommentRoundTrips() {
        let annotation = Annotation(
            id: "abc123abc123", kind: .highlight, quote: "q", note: "n", color: .yellow,
            locator: Locator(fraction: 0.5, label: "§ 3 --> [end] <b>"),
            chapter: "Ch --> 1 <!-- x -->", tags: ["a-->b", "\"quoted\"", "back\\slash"],
            createdAt: date("2026-01-01T00:00:00Z"))
        let markdown = document([annotation]).markdown()
        let machineLines = markdown.split(separator: "\n").filter { $0.hasPrefix("<!-- coreader") }
        #expect(machineLines.count == 1)
        #expect(machineLines[0].components(separatedBy: "-->").count == 2, "only the closing --> may appear in the comment")
        #expect(roundTrip(annotation) == annotation)
    }

    @Test func textIsNormalisedNotLost() {
        let messy = highlight("abc123abc123", at: 0.1, quote: "win\r\ndows\rmac", note: "\n\n  \nnote body\r\nsecond\n\n\n")
        let clean = roundTrip(messy)
        #expect(clean?.quote == "win\ndows\nmac")
        #expect(clean?.note == "note body\nsecond")
        // Dates are kept to the second.
        var precise = highlight("abc123abc123", at: 0.1)
        precise.createdAt = Date(timeIntervalSince1970: 1_700_000_000.789)
        #expect(roundTrip(precise)?.createdAt == Date(timeIntervalSince1970: 1_700_000_000))
        // An empty chapter is no chapter.
        #expect(roundTrip(highlight("abc123abc123", at: 0.1, chapter: "  "))?.chapter == nil)
    }

    @Test func writingIsAFixedPoint() {
        let annotations = [
            highlight("a00000000000", at: 0.1, quote: "x\n\ny", note: "- list\n\n## heading", chapter: "One", tags: ["t"]),
            highlight("b00000000000", at: 0.2, quote: "", note: "> starts with quote", chapter: "One"),
            highlight("c00000000000", at: 0.3, quote: "only quote"),
        ]
        var doc = document(annotations)
        doc.preamble = "My reading plan.\n\n- one\n- two"
        doc.trailer = "## My summary\n\nIt was good."
        doc.interleaved = ["a00000000000": "A thought between notes."]
        doc.extraFrontMatter = ["tags:", "  - books", "aliases: [TFS]"]
        let first = doc.markdown()
        let parsed = NotesDocument.parse(first)
        #expect(parsed == doc)
        #expect(parsed.markdown() == first)
    }
}

extension AnnotationKind {
    static let allKinds: [AnnotationKind] = [.highlight, .note, .image]
}

@Suite struct NotesDocumentHumanEditTests {
    private let original = document([
        highlight("a00000000000", at: 0.1, quote: "First passage.", note: "First note.", chapter: "Chapter One", page: 4),
        highlight("b00000000000", at: 0.2, quote: "Second passage.", note: "", chapter: "Chapter One", page: 9),
        highlight("c00000000000", at: 0.6, quote: "Third passage.", note: "Third note.", chapter: "Chapter Two", page: 30),
    ])

    @Test func editedQuoteAndNoteTextWins() {
        let edited = original.markdown()
            .replacingOccurrences(of: "> First passage.", with: "> First passage, corrected by hand.\n> And extended.")
            .replacingOccurrences(of: "First note.", with: "First note, rewritten.\n\n- with a list\n- of two items")
            .replacingOccurrences(of: "> Second passage.\n", with: "> Second passage.\n\nA note added in Obsidian.\n")
        let parsed = NotesDocument.parse(edited)
        #expect(parsed.annotations[0].quote == "First passage, corrected by hand.\nAnd extended.")
        #expect(parsed.annotations[0].note == "First note, rewritten.\n\n- with a list\n- of two items")
        #expect(parsed.annotations[1].note == "A note added in Obsidian.")
        // Everything the comment owns is untouched.
        #expect(parsed.annotations.map(\.id) == original.annotations.map(\.id))
        #expect(parsed.annotations.map(\.locator) == original.annotations.map(\.locator))
        #expect(parsed.annotations.map(\.chapter) == original.annotations.map(\.chapter))
    }

    @Test func textOutsideBlocksIsKeptWhereItWas() {
        let edited = original.markdown()
            .replacingOccurrences(of: "# Thinking, Fast and Slow\n", with: "# Thinking, Fast and Slow\n\nRead on holiday.\n\n## Why I picked this up\n\nA friend insisted.\n")
            .replacingOccurrences(of: "&a=a00000000000)\n", with: "&a=a00000000000)\n\nA paragraph of my own between two notes.\n")
            + "\n## My summary\n\nTwo systems. One lazy.\n\n- point one\n- point two\n"
        let parsed = NotesDocument.parse(edited)
        #expect(parsed.annotations == original.annotations)
        #expect(parsed.preamble == "Read on holiday.\n\n## Why I picked this up\n\nA friend insisted.")
        #expect(parsed.interleaved == ["a00000000000": "A paragraph of my own between two notes."])
        #expect(parsed.trailer == "## My summary\n\nTwo systems. One lazy.\n\n- point one\n- point two")

        let rewritten = parsed.markdown()
        #expect(rewritten == edited, "the app writes back exactly what the person had")
    }

    @Test func renamingAChapterHeadingRenamesTheChapter() {
        let edited = original.markdown().replacingOccurrences(of: "## Chapter One", with: "## 1. The Beginning")
        let parsed = NotesDocument.parse(edited)
        #expect(parsed.annotations.map(\.chapter) == ["1. The Beginning", "1. The Beginning", "Chapter Two"])
        #expect(parsed.preamble.isEmpty && parsed.interleaved.isEmpty)
        let rewritten = parsed.markdown()
        #expect(!rewritten.contains("Chapter One"))
        #expect(rewritten.components(separatedBy: "## 1. The Beginning").count == 2)
    }

    @Test func aHeadingAboveAnUnchapteredBlockAssignsItsChapter() {
        let doc = document([highlight("a00000000000", at: 0.1), highlight("b00000000000", at: 0.2)])
        let edited = doc.markdown().replacingOccurrences(of: "\n<!-- coreader {\"id\":\"b0", with: "\n## Later\n\n<!-- coreader {\"id\":\"b0")
        #expect(NotesDocument.parse(edited).annotations.map(\.chapter) == [nil, "Later"])
    }

    @Test func deletingALinkLineLosesNothing() {
        let edited = original.markdown()
            .replacingOccurrences(of: "[p. 5](coreader://open?book=\(bookID)&a=a00000000000)\n\n", with: "")
            .replacingOccurrences(of: "[p. 10](coreader://open?book=\(bookID)&a=b00000000000)\n\n", with: "")
        #expect(!edited.contains("a00000000000)"))
        let parsed = NotesDocument.parse(edited)
        #expect(parsed.annotations == original.annotations, "the next block's chapter heading is not swallowed by the note")
        #expect(parsed.markdown() == original.markdown(), "the link lines come back on the next write")
    }

    @Test func deletingAWholeBlockDeletesTheAnnotation() {
        var lines = original.markdown().components(separatedBy: "\n")
        let start = lines.firstIndex { $0.contains("\"id\":\"b00000000000\"") }!
        let end = lines.firstIndex { $0.hasSuffix("&a=b00000000000)") }!
        lines.removeSubrange(start...end)
        let parsed = NotesDocument.parse(lines.joined(separator: "\n"))
        #expect(parsed.annotations.map(\.id) == ["a00000000000", "c00000000000"])
        #expect(parsed.interleaved.isEmpty)
    }

    @Test func aHandWrittenBlockWithOnlyAnIDIsAccepted() {
        let markdown = """
            # My own notes file

            Some intro.

            <!-- coreader {"id":"handmade0001"} -->
            > A quote I typed myself.

            And what I think about it.
            """
        let parsed = NotesDocument.parse(markdown)
        #expect(parsed.title == "My own notes file")
        #expect(parsed.preamble == "Some intro.")
        let annotation = try! #require(parsed.annotations.first)
        #expect(annotation.id == "handmade0001")
        #expect(annotation.kind == .highlight)
        #expect(annotation.quote == "A quote I typed myself.")
        #expect(annotation.note == "And what I think about it.")
        #expect(annotation.locator.fraction == 0)
    }

    @Test func aDamagedCommentBecomesTextInsteadOfVanishing() {
        let edited = original.markdown().replacingOccurrences(of: "{\"id\":\"b00000000000\"", with: "{\"id\":b00000000000\"")
        let parsed = NotesDocument.parse(edited)
        #expect(parsed.annotations.map(\.id) == ["a00000000000", "c00000000000"])
        let leftover = try! #require(parsed.interleaved["a00000000000"])
        #expect(leftover.contains("> Second passage."))
        #expect(leftover.contains("<!-- coreader {\"id\":b00000000000\""))
        // And it survives the next write, still as the user's text.
        let again = NotesDocument.parse(parsed.markdown())
        #expect(again.annotations.map(\.id) == ["a00000000000", "c00000000000"])
        #expect(again.interleaved["a00000000000"]?.contains("> Second passage.") == true)
    }

    @Test func foreignFrontMatterAndLineEndingsAreTolerated() {
        let markdown = "\u{FEFF}---\r\ntitle: Plain Title\r\nauthors: [Ann Author, \"Bob, Jr.\"]\r\ntags:\r\n  - reading\r\n  - psychology\r\ncoreader_id: 'abc'\r\nrating: 5\r\n# a yaml comment\r\nsource: coreader\r\n---\r\n\r\n# Plain Title\r\n\r\n<!-- coreader {\"id\":\"x00000000000\",\"locator\":{\"fraction\":0.5}} -->\r\n> Quote\r\n\r\nNote\r\n"
        let parsed = NotesDocument.parse(markdown)
        #expect(parsed.title == "Plain Title")
        #expect(parsed.authors == ["Ann Author", "Bob, Jr."])
        #expect(parsed.bookID == "abc")
        #expect(parsed.extraFrontMatter == ["tags:", "  - reading", "  - psychology", "rating: 5", "# a yaml comment"])
        #expect(parsed.annotations.first?.quote == "Quote")
        #expect(parsed.annotations.first?.note == "Note")
        let rewritten = parsed.markdown()
        #expect(rewritten.contains("\ntags:\n  - reading\n  - psychology\nrating: 5\n# a yaml comment\n---\n"))
        #expect(NotesDocument.parse(rewritten).extraFrontMatter == parsed.extraFrontMatter)
    }

    @Test func aFileWithNoCoreaderContentIsAllPreamble() {
        let markdown = "Just some notes I wrote.\n\n## Section\n\n- a\n- b\n"
        let parsed = NotesDocument.parse(markdown)
        #expect(parsed.annotations.isEmpty)
        #expect(parsed.preamble == "Just some notes I wrote.\n\n## Section\n\n- a\n- b")
        #expect(NotesDocument.parse("").annotations.isEmpty)
    }
}
