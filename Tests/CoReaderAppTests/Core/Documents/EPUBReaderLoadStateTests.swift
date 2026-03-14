import Foundation
import Testing
@testable import CoReaderApp

struct EPUBReaderLoadStateTests {
    @Test
    func latestLoadReplacesEarlierPendingRequest() {
        var state = EPUBReaderLoadState()

        let firstRequestID = state.startLoading(fileURL: URL(fileURLWithPath: "/tmp/First.epub"))
        let secondRequestID = state.startLoading(fileURL: URL(fileURLWithPath: "/tmp/Second.epub"))

        #expect(state.accepts(requestID: firstRequestID, fileURL: URL(fileURLWithPath: "/tmp/First.epub")) == false)
        #expect(state.accepts(requestID: secondRequestID, fileURL: URL(fileURLWithPath: "/tmp/Second.epub")) == true)
    }

    @Test
    func matchingLoadAcceptsStandardizedFileURLVariants() {
        var state = EPUBReaderLoadState()
        let requestID = state.startLoading(fileURL: URL(fileURLWithPath: "/tmp/Books/../Books/Guide.epub"))

        #expect(state.accepts(requestID: requestID, fileURL: URL(fileURLWithPath: "/tmp/Books/Guide.epub")))
    }
}
