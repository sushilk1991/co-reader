import Testing
@testable import CoReaderApp

struct DocumentContextComposerTests {
    @Test
    func composerPrefersSelectionThenVisiblePageThenChunks() {
        let composer = DocumentContextComposer()
        let pages = [
            "Page one introduces the history of expert systems.",
            "Page two explains multi-head attention and transformer blocks in detail.",
            "Page three covers training dynamics and scaling laws.",
            "Page four discusses inference serving and retrieval systems."
        ]

        let context = composer.compose(
            title: "Agentic Mesh",
            question: "Summarize the transformer section",
            selection: DocumentSelection(
                text: "multi-head attention and transformer blocks",
                pageIndex: 1,
                surroundingText: "Page two explains multi-head attention and transformer blocks in detail."
            ),
            currentPageIndex: 1,
            visiblePageIndexes: [1, 2],
            pageTexts: pages
        )

        #expect(context.excerpt.contains("Selection Focus"))
        #expect(context.excerpt.contains("multi-head attention and transformer blocks"))
        #expect(context.excerpt.contains("[Page 2]"))
    }

    @Test
    func composerFallsBackToRelevantPagesWhenNoSelectionOrVisiblePage() {
        let composer = DocumentContextComposer()
        let pages = [
            "This introduction discusses background trends in AI.",
            "The CAP theorem describes tradeoffs between consistency, availability, and partition tolerance.",
            "Appendix material covers references and glossary."
        ]

        let context = composer.compose(
            title: "Distributed Systems",
            question: "Explain the CAP theorem tradeoffs",
            selection: nil,
            currentPageIndex: nil,
            visiblePageIndexes: [],
            pageTexts: pages
        )

        #expect(context.excerpt.contains("Relevant Sections"))
        #expect(context.excerpt.contains("CAP theorem"))
        #expect(context.excerpt.contains("[Page 2]"))
    }
}
