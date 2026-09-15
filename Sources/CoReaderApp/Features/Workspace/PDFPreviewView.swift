import PDFKit
import SwiftUI

struct PDFPreviewView: NSViewRepresentable {
    let fileURL: URL
    let initialPageIndex: Int?
    let highlights: [PDFDocumentHighlight]
    let isHighlightToolEnabled: Bool
    let selectedHighlightColor: ReaderHighlightColor
    let onSelectionChange: @MainActor (DocumentSelection?) -> Void
    let onReadingPositionChange: @MainActor (Int?, [Int]) -> Void
    let onPageCountChange: @MainActor (Int) -> Void
    let onHighlightCapture: @MainActor ([PDFDocumentHighlightDraft]) -> Void
    let onHighlightRemoval: @MainActor (UUID) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> HighlightingPDFView {
        let view = HighlightingPDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.backgroundColor = .textBackgroundColor
        view.displaysPageBreaks = true
        context.coordinator.attach(to: view)
        context.coordinator.updateDocumentIfNeeded(fileURL, in: view)
        context.coordinator.syncHighlightConfiguration(in: view)
        context.coordinator.syncHighlights(in: view)
        return view
    }

    func updateNSView(_ nsView: HighlightingPDFView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.updateDocumentIfNeeded(fileURL, in: nsView)
        context.coordinator.syncHighlightConfiguration(in: nsView)
        context.coordinator.syncHighlights(in: nsView)
    }

    @MainActor
    final class Coordinator: NSObject {
        /// Upper bound on waiting for PDFKit to confirm the restored page.
        private static let restoreSettleTimeout: Duration = .milliseconds(1_500)

        var parent: PDFPreviewView
        private var loadedFileURL: URL?
        private var lastSyncedHighlights: [PDFDocumentHighlight]?
        private var restoreState = ReadingPositionRestoreState()
        private var restoreTimeoutTask: Task<Void, Never>?

        init(parent: PDFPreviewView) {
            self.parent = parent
            super.init()
        }

        deinit {
            NotificationCenter.default.removeObserver(self)
        }

        func attach(to pdfView: HighlightingPDFView) {
            NotificationCenter.default.removeObserver(self)
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleSelectionChanged),
                name: Notification.Name.PDFViewSelectionChanged,
                object: pdfView
            )
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handlePageChanged),
                name: Notification.Name.PDFViewPageChanged,
                object: pdfView
            )
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleVisiblePagesChanged),
                name: Notification.Name.PDFViewVisiblePagesChanged,
                object: pdfView
            )
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleDocumentChanged),
                name: Notification.Name.PDFViewDocumentChanged,
                object: pdfView
            )
            pdfView.onLayout = { [weak self, weak pdfView] in
                guard let self, let pdfView else {
                    return
                }

                self.applyRestoreStep(self.restoreState.noteLayout(currentPageIndex: self.currentPageIndex(of: pdfView)), in: pdfView)
            }
        }

        func updateDocumentIfNeeded(_ fileURL: URL, in pdfView: HighlightingPDFView) {
            let normalizedURL = fileURL.standardizedFileURL
            guard loadedFileURL != normalizedURL else {
                return
            }

            loadedFileURL = normalizedURL
            lastSyncedHighlights = nil
            let document = PDFDocument(url: normalizedURL)
            pdfView.document = document
            parent.onPageCountChange(document?.pageCount ?? 0)
            beginRestore(in: pdfView)
            publishSelection(for: pdfView)
            publishReadingPosition(for: pdfView)
        }

        func syncHighlightConfiguration(in pdfView: HighlightingPDFView) {
            pdfView.isHighlightToolEnabled = parent.isHighlightToolEnabled
            pdfView.selectedHighlightColor = parent.selectedHighlightColor
            pdfView.onHighlightCapture = { [weak self] drafts in
                guard let self else {
                    return
                }

                self.parent.onHighlightCapture(drafts)
            }
            pdfView.onHighlightRemoval = { [weak self] highlightID in
                guard let self else {
                    return
                }

                self.parent.onHighlightRemoval(highlightID)
            }
        }

        /// `updateNSView` runs on every observable change the panel reads; only touch
        /// PDFKit when the highlight list itself changed.
        func syncHighlights(in pdfView: HighlightingPDFView) {
            guard lastSyncedHighlights != parent.highlights else {
                return
            }

            lastSyncedHighlights = parent.highlights
            pdfView.syncManagedHighlights(parent.highlights)
        }

        // MARK: Reading position restore

        private func beginRestore(in pdfView: HighlightingPDFView) {
            restoreTimeoutTask?.cancel()
            restoreState.begin(target: parent.initialPageIndex, pageCount: pdfView.document?.pageCount ?? 0)
            applyRestoreStep(restoreState.notePageChange(currentPageIndex: currentPageIndex(of: pdfView)), in: pdfView)

            guard restoreState.isPending else {
                return
            }

            restoreTimeoutTask = Task { [weak self, weak pdfView] in
                try? await Task.sleep(for: Self.restoreSettleTimeout)
                guard !Task.isCancelled, let self, let pdfView else {
                    return
                }

                self.applyRestoreStep(self.restoreState.expire(), in: pdfView)
            }
        }

        private func applyRestoreStep(_ action: ReadingPositionRestoreState.Action, in pdfView: HighlightingPDFView) {
            switch action {
            case .none:
                return
            case let .goTo(pageIndex):
                guard let page = pdfView.document?.page(at: pageIndex) else {
                    return
                }
                pdfView.go(to: page)
            case .settled, .gaveUp:
                restoreTimeoutTask?.cancel()
                publishReadingPosition(for: pdfView)
            }
        }

        private func currentPageIndex(of pdfView: PDFView) -> Int? {
            pdfView.currentPage.flatMap { pdfView.document?.index(for: $0) }
        }

        private func publishSelection(for pdfView: PDFView) {
            let normalizedSelection = pdfView.currentSelection?
                .string?
                .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)

            guard let normalizedSelection, !normalizedSelection.isEmpty else {
                parent.onSelectionChange(nil)
                return
            }

            let anchorPage = pdfView.currentSelection?.pages.first ?? pdfView.currentPage
            let pageIndex = anchorPage.flatMap { pdfView.document?.index(for: $0) } ?? 0
            let surroundingText = anchorPage?.string?
                .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? normalizedSelection

            let selection = DocumentSelection(
                text: normalizedSelection,
                pageIndex: pageIndex,
                surroundingText: String(surroundingText.prefix(2_000))
            )

            parent.onSelectionChange(selection)
        }

        /// Suppressed while a restore is pending, otherwise PDFKit's interim page 0
        /// would overwrite the saved position.
        private func publishReadingPosition(for pdfView: PDFView) {
            guard !restoreState.isPending else {
                return
            }

            let visiblePageIndexes = pdfView.visiblePages
                .compactMap { pdfView.document?.index(for: $0) }
                .sorted()

            parent.onReadingPositionChange(currentPageIndex(of: pdfView), visiblePageIndexes)
        }

        @objc
        private func handleSelectionChanged(_ notification: Notification) {
            guard let pdfView = notification.object as? PDFView else {
                return
            }

            publishSelection(for: pdfView)
        }

        @objc
        private func handlePageChanged(_ notification: Notification) {
            guard let pdfView = notification.object as? HighlightingPDFView else {
                return
            }

            if restoreState.isPending {
                applyRestoreStep(restoreState.notePageChange(currentPageIndex: currentPageIndex(of: pdfView)), in: pdfView)
                return
            }

            publishReadingPosition(for: pdfView)
        }

        @objc
        private func handleVisiblePagesChanged(_ notification: Notification) {
            guard let pdfView = notification.object as? PDFView else {
                return
            }

            publishReadingPosition(for: pdfView)
        }

        @objc
        private func handleDocumentChanged(_ notification: Notification) {
            guard let pdfView = notification.object as? HighlightingPDFView else {
                return
            }

            lastSyncedHighlights = nil
            publishSelection(for: pdfView)
            publishReadingPosition(for: pdfView)
            syncHighlights(in: pdfView)
        }
    }
}
