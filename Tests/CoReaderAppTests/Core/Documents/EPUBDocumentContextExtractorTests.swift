import Foundation
import Testing
@testable import CoReaderApp

struct EPUBDocumentContextExtractorTests {
    @Test
    func extractorUsesCurrentChapterTextForEPUBDocuments() throws {
        let extractor = LiveDocumentContextExtractor(
            epubLoader: StubEPUBBookLoader(
                book: EPUBBook(
                    title: "Distributed Reading",
                    rootURL: URL(fileURLWithPath: "/tmp/epub-root"),
                    sections: [
                        EPUBSection(
                            id: "intro",
                            title: "Introduction",
                            contentURL: URL(fileURLWithPath: "/tmp/epub-root/intro.xhtml"),
                            textContent: "This chapter introduces replicated logs."
                        ),
                        EPUBSection(
                            id: "quorum",
                            title: "Quorum Writes",
                            contentURL: URL(fileURLWithPath: "/tmp/epub-root/quorum.xhtml"),
                            textContent: "Quorum writes trade latency for stronger durability guarantees."
                        )
                    ]
                )
            )
        )

        let context = try extractor.extractContext(
            for: ReaderDocument(fileURL: URL(fileURLWithPath: "/tmp/Distributed Reading.epub")),
            question: "How do quorum writes affect durability?",
            selection: nil,
            currentPageIndex: 1,
            visiblePageIndexes: []
        )

        #expect(context.title == "Distributed Reading")
        #expect(context.excerpt.contains("[Chapter 2]"))
        #expect(context.excerpt.contains("Quorum writes trade latency for stronger durability guarantees."))
        #expect(!context.excerpt.contains("EPUB support is imported into the workspace"))
    }
}

private struct StubEPUBBookLoader: EPUBBookLoading {
    let book: EPUBBook

    func loadBook(from fileURL: URL) throws -> EPUBBook {
        book
    }
}
