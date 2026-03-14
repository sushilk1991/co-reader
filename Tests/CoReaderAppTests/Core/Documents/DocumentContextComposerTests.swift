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
            scope: .selection,
            selection: DocumentSelection(
                text: "multi-head attention and transformer blocks",
                pageIndex: 1,
                surroundingText: "Page two explains multi-head attention and transformer blocks in detail."
            ),
            currentPageIndex: 1,
            visiblePageIndexes: [1, 2],
            pageTexts: pages
        )

        #expect(context.excerpt.contains("Context Scope"))
        #expect(context.excerpt.contains("Selection"))
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
            scope: .focus,
            selection: nil,
            currentPageIndex: nil,
            visiblePageIndexes: [],
            pageTexts: pages
        )

        #expect(context.excerpt.contains("Reading Context"))
        #expect(context.excerpt.contains("CAP theorem"))
        #expect(context.excerpt.contains("[Page 2]"))
    }

    @Test
    func selectionScopeStaysAnchoredToTheSelectionUnit() {
        let composer = DocumentContextComposer()
        let pages = [
            "Preface material that should stay out of scope.",
            "Chapter two explains vector clocks and causality in distributed systems.",
            "Appendix material that should stay out of scope."
        ]

        let context = composer.compose(
            title: "Distributed Systems",
            question: "Explain the selected causality passage",
            scope: .selection,
            selection: DocumentSelection(
                text: "vector clocks and causality",
                pageIndex: 1,
                surroundingText: "Chapter two explains vector clocks and causality in distributed systems."
            ),
            currentPageIndex: 1,
            visiblePageIndexes: [1],
            pageTexts: pages
        )

        #expect(context.excerpt.contains("Selection"))
        #expect(context.excerpt.contains("vector clocks and causality"))
        #expect(context.excerpt.contains("[Page 2]"))
        #expect(!context.excerpt.contains("[Page 1]"))
        #expect(!context.excerpt.contains("[Page 3]"))
    }

    @Test
    func documentScopeSamplesAcrossTheWholeDocumentForBroadQuestions() {
        let composer = DocumentContextComposer()
        let pages = [
            "Introduction: distributed systems start with replication and fault tolerance.",
            "Chapter one: consistency models shape what readers can assume about data freshness.",
            "Chapter two: leader election stabilizes cluster decisions and failover.",
            "Chapter three: quorum writes trade latency for stronger durability guarantees.",
            "Chapter four: observability and debugging reveal systemic bottlenecks.",
            "Conclusion: CRDTs and edge replication point toward future architectures."
        ]

        let context = composer.compose(
            title: "Distributed Systems",
            question: "Summarize the whole document",
            scope: .document,
            selection: nil,
            currentPageIndex: nil,
            visiblePageIndexes: [],
            pageTexts: pages
        )

        #expect(context.excerpt.contains("Document Sweep"))
        #expect(context.excerpt.contains("[Page 1]"))
        #expect(context.excerpt.contains("[Page 6]"))
        #expect(context.excerpt.count < 4_500)
    }
}
