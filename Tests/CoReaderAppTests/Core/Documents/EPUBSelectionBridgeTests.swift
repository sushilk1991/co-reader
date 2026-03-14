import Foundation
import Testing
@testable import CoReaderApp

struct EPUBSelectionBridgeTests {
    @Test
    func payloadBuildsDocumentSelectionForChapterIndex() {
        let payload = EPUBSelectionPayload(
            text: "  Intelligent agents coordinate through shared context.  ",
            surroundingText: "\nThis chapter explains how intelligent agents coordinate through shared context and memory.\n"
        )

        let selection = payload.documentSelection(chapterIndex: 2)

        #expect(selection == DocumentSelection(
            text: "Intelligent agents coordinate through shared context.",
            pageIndex: 2,
            surroundingText: "This chapter explains how intelligent agents coordinate through shared context and memory."
        ))
    }

    @Test
    func payloadDropsWhitespaceOnlySelections() {
        let payload = EPUBSelectionPayload(
            text: "   \n\t  ",
            surroundingText: "Nearby context that should never be published."
        )

        #expect(payload.documentSelection(chapterIndex: 0) == nil)
    }

    @Test
    func payloadFallsBackToSelectedTextWhenContextIsEmpty() {
        let payload = EPUBSelectionPayload(
            text: "A compact chapter summary",
            surroundingText: "   "
        )

        #expect(payload.documentSelection(chapterIndex: 4)?.surroundingText == "A compact chapter summary")
    }

    @Test
    func messageBodyDictionaryBuildsSelection() {
        let body: [String: Any] = [
            "text": "  Agent memory needs deliberate compression. ",
            "surroundingText": "\nAgent memory needs deliberate compression to stay useful over time.\n"
        ]

        #expect(
            EPUBSelectionPayload.selection(fromMessageBody: body, chapterIndex: 1) == DocumentSelection(
                text: "Agent memory needs deliberate compression.",
                pageIndex: 1,
                surroundingText: "Agent memory needs deliberate compression to stay useful over time."
            )
        )
    }

    @Test
    func invalidMessageBodyReturnsNil() {
        #expect(EPUBSelectionPayload.selection(fromMessageBody: ["unknown": "value"], chapterIndex: 3) == nil)
    }
}
