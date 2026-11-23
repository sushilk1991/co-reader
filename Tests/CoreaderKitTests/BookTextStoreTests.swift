import Foundation
import Testing
@testable import CoreaderKit
#if canImport(PDFKit)
import CoreGraphics
import CoreText
#endif

@Suite struct BookTextStoreTests {
    let temp = TempDirectory()
    var store: BookTextStore { BookTextStore(cachesRoot: temp.url.appendingPathComponent("Caches")) }
    let book = Book(id: "book-1", title: "A Book", format: .epub, fileName: "a-book.epub")

    private let sections = [
        BookTextStore.Section(index: 0, title: "Preface", locator: Locator(cfi: "epubcfi(/6/2!)", fraction: 0), text: "Short preface."),
        BookTextStore.Section(index: 1, title: "Chapter 1: Über Alles & More", locator: Locator(cfi: "epubcfi(/6/4!)", fraction: 0.25),
                              text: "First line.\n\n# A heading inside the text\n\nLast line without newline"),
        BookTextStore.Section(index: 2, title: "", locator: Locator(fraction: 0.9), text: ""),
        BookTextStore.Section(index: 7, title: "Notes", locator: Locator(fraction: 0.95), text: "\n\nstarts and ends with blank lines\n\n"),
    ]

    @Test func savesReadableFilesAndLoadsThemBack() throws {
        #expect(!store.hasText(for: book.id))
        #expect(throws: BookTextStore.TextError.noText(book.id)) { try store.load(for: book.id) }

        try store.save(sections, for: book)
        #expect(store.hasText(for: book.id))
        #expect(try store.load(for: book.id) == sections)

        let folder = store.folder(for: book.id)
        #expect(folder.path == temp.url.appendingPathComponent("Caches/text/book-1").path)
        let names = try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted()
        #expect(names == ["001-preface.md", "002-chapter-1-uber-alles-more.md", "003-section.md", "004-notes.md", "index.json"])
        #expect(try store.sectionFiles(for: book.id).map(\.lastPathComponent) == Array(names.dropLast()))

        let second = try String(contentsOf: folder.appendingPathComponent(names[1]), encoding: .utf8)
        #expect(second == "# Chapter 1: Über Alles & More\n\n[Open in Coreader](coreader://open?book=book-1&cfi=epubcfi(/6/4!))\n\nFirst line.\n\n# A heading inside the text\n\nLast line without newline")
    }

    @Test func savingAgainReplacesTheOldSections() throws {
        try store.save(sections, for: book)
        let fewer = [BookTextStore.Section(index: 0, title: "Only", locator: Locator(fraction: 0), text: "one")]
        try store.save(fewer, for: book)
        #expect(try store.load(for: book.id) == fewer)
        #expect(try FileManager.default.contentsOfDirectory(atPath: store.folder(for: book.id).path).sorted() == ["001-only.md", "index.json"])
        // No staging folders are left next to it.
        #expect(try FileManager.default.contentsOfDirectory(atPath: store.folder(for: book.id).deletingLastPathComponent().path) == ["book-1"])
    }

    @Test func bookIDsCannotEscapeTheCache() {
        let folder = store.folder(for: "../../etc/passwd")
        #expect(folder.deletingLastPathComponent().path == temp.url.appendingPathComponent("Caches/text").path)
        #expect(!folder.lastPathComponent.contains("/") && !folder.lastPathComponent.contains("."))
    }

    #if canImport(PDFKit)
    @Test func extractsOneSectionPerPDFPage() throws {
        let url = temp.url.appendingPathComponent("three pages.pdf")
        makePDF(pages: ["Alpha page text", "Beta page text", "Gamma page text"], at: url)
        let pdfBook = Book(id: "pdf-1", title: "Three Pages", format: .pdf, fileName: "three-pages.pdf")

        let extracted = try store.extractPDF(at: url, book: pdfBook)
        #expect(extracted.map(\.title) == ["Page 1", "Page 2", "Page 3"])
        #expect(extracted.map(\.index) == [0, 1, 2])
        #expect(extracted.map(\.locator.page) == [0, 1, 2])
        #expect(extracted.map(\.locator.fraction) == [0, 1.0 / 3, 2.0 / 3])
        #expect(extracted[1].text.contains("Beta page text"))
        #expect(!extracted[1].text.contains("Alpha"))

        try store.save(extracted, for: pdfBook)
        #expect(try store.load(for: "pdf-1") == extracted)
        let first = try String(contentsOf: try store.sectionFiles(for: "pdf-1")[0], encoding: .utf8)
        #expect(first.hasPrefix("# Page 1\n\n[Open in Coreader](coreader://open?book=pdf-1&page=1)\n\n"))
    }

    @Test func aFileThatIsNotAPDFIsAnError() throws {
        let fake = temp.file("fake.pdf", "this is not a pdf")
        #expect(throws: BookTextStore.TextError.unreadablePDF(fake.path)) {
            try store.extractPDF(at: fake, book: book)
        }
    }
    #endif
}

#if canImport(PDFKit)
/// A real PDF with one line of text per page, drawn with Core Text.
func makePDF(pages: [String], at url: URL) {
    var box = CGRect(x: 0, y: 0, width: 612, height: 792)
    let context = CGContext(url as CFURL, mediaBox: &box, nil)!
    let font = CTFontCreateWithName("Helvetica" as CFString, 14, nil)
    for text in pages {
        context.beginPDFPage(nil)
        let attributed = NSAttributedString(string: text, attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font])
        context.textPosition = CGPoint(x: 72, y: 700)
        CTLineDraw(CTLineCreateWithAttributedString(attributed), context)
        context.endPDFPage()
    }
    context.closePDF()
}
#endif
