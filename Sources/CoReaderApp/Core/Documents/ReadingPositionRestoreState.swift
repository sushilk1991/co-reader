/// Drives jumping back to a saved page once a PDF loads.
///
/// PDFKit resets to the first page while it lays the document out, so a single
/// `go(to:)` right after `document =` is often undone. The target is re-applied
/// on each page-change or layout until a layout pass shows it in place, and
/// position updates are suppressed meanwhile so page 0 never overwrites the
/// saved page. Attempts are capped so a user who scrolls is not fought.
///
/// ```
///  begin(target) ──▶ pending ──notePageChange/noteLayout(current)──┐
///                       ▲                                          │
///                       │  current ≠ target, attempts left ──▶ .goTo(target)
///                       │  current = target, layout seen   ──▶ .settled
///                       └─ attempts exhausted              ──▶ .gaveUp
/// ```
struct ReadingPositionRestoreState: Equatable, Sendable {
    enum Action: Equatable, Sendable {
        case none
        case goTo(pageIndex: Int)
        case settled
        case gaveUp
    }

    static let maxAttempts = 4

    private var target: Int?
    private var attemptsLeft = 0
    private var layoutSeen = false

    /// While pending, the view must not publish its reading position.
    var isPending: Bool {
        target != nil
    }

    /// Page 0 needs no restore: that is where PDFKit opens anyway.
    mutating func begin(target: Int?, pageCount: Int) {
        layoutSeen = false
        guard let target, target > 0, target < pageCount else {
            self.target = nil
            attemptsLeft = 0
            return
        }

        self.target = target
        attemptsLeft = Self.maxAttempts
    }

    mutating func notePageChange(currentPageIndex: Int?) -> Action {
        step(currentPageIndex: currentPageIndex)
    }

    /// A layout pass means the view has real geometry, so reaching the target
    /// after one counts as done.
    mutating func noteLayout(currentPageIndex: Int?) -> Action {
        layoutSeen = true
        return step(currentPageIndex: currentPageIndex)
    }

    /// Bounded fallback: stop waiting even if no layout pass confirmed the page.
    mutating func expire() -> Action {
        guard target != nil else {
            return .none
        }

        finish()
        return .gaveUp
    }

    private mutating func step(currentPageIndex: Int?) -> Action {
        guard let target else {
            return .none
        }

        if currentPageIndex == target {
            guard layoutSeen else {
                return .none
            }

            finish()
            return .settled
        }

        guard attemptsLeft > 0 else {
            finish()
            return .gaveUp
        }

        attemptsLeft -= 1
        return .goTo(pageIndex: target)
    }

    private mutating func finish() {
        target = nil
        attemptsLeft = 0
    }
}
