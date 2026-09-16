import Testing
@testable import CoReaderApp

struct ReadingPositionRestoreStateTests {
    /// PDFKit's interim page 0 must trigger a re-apply, and publishing stays
    /// suppressed until a layout pass shows the target page.
    @Test
    func interimPageZeroIsCorrectedUntilLayoutConfirmsTarget() {
        var state = ReadingPositionRestoreState()
        state.begin(target: 7, pageCount: 20)

        #expect(state.isPending)
        #expect(state.notePageChange(currentPageIndex: 0) == .goTo(pageIndex: 7))
        #expect(state.notePageChange(currentPageIndex: 7) == .none)
        #expect(state.isPending)
        #expect(state.noteLayout(currentPageIndex: 0) == .goTo(pageIndex: 7))
        #expect(state.notePageChange(currentPageIndex: 7) == .settled)
        #expect(!state.isPending)
        #expect(state.notePageChange(currentPageIndex: 0) == .none)
    }

    @Test
    func givesUpAfterMaxAttemptsSoTheUserIsNotFought() {
        var state = ReadingPositionRestoreState()
        state.begin(target: 3, pageCount: 10)

        for _ in 0 ..< ReadingPositionRestoreState.maxAttempts {
            #expect(state.noteLayout(currentPageIndex: 0) == .goTo(pageIndex: 3))
        }

        #expect(state.noteLayout(currentPageIndex: 0) == .gaveUp)
        #expect(!state.isPending)
    }

    @Test
    func pageZeroAndOutOfRangeTargetsNeedNoRestore() {
        var state = ReadingPositionRestoreState()

        state.begin(target: 0, pageCount: 10)
        #expect(!state.isPending)

        state.begin(target: 10, pageCount: 10)
        #expect(!state.isPending)

        state.begin(target: nil, pageCount: 10)
        #expect(!state.isPending)
    }

    @Test
    func expireEndsAPendingRestore() {
        var state = ReadingPositionRestoreState()
        state.begin(target: 4, pageCount: 10)

        #expect(state.expire() == .gaveUp)
        #expect(!state.isPending)
        #expect(state.expire() == .none)
    }
}
