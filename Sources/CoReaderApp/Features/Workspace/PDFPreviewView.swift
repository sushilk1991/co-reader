import PDFKit
import SwiftUI

struct PDFPreviewView: NSViewRepresentable {
    let fileURL: URL
    let onSelectionChange: @MainActor (DocumentSelection?) -> Void
    let onReadingPositionChange: @MainActor (Int?, [Int]) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.backgroundColor = .textBackgroundColor
        view.displaysPageBreaks = true
        context.coordinator.attach(to: view)
        context.coordinator.updateDocumentIfNeeded(fileURL, in: view)
        return view
    }

    func updateNSView(_ nsView: PDFView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.updateDocumentIfNeeded(fileURL, in: nsView)
    }

    @MainActor
    final class Coordinator: NSObject {
        var parent: PDFPreviewView
        private var loadedFileURL: URL?

        init(parent: PDFPreviewView) {
            self.parent = parent
            super.init()
        }

        deinit {
            NotificationCenter.default.removeObserver(self)
        }

        func attach(to pdfView: PDFView) {
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
        }

        func updateDocumentIfNeeded(_ fileURL: URL, in pdfView: PDFView) {
            let normalizedURL = fileURL.standardizedFileURL
            guard loadedFileURL != normalizedURL else {
                return
            }

            loadedFileURL = normalizedURL
            pdfView.document = PDFDocument(url: normalizedURL)
            publishSelection(for: pdfView)
            publishReadingPosition(for: pdfView)
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

        private func publishReadingPosition(for pdfView: PDFView) {
            let currentPageIndex = pdfView.currentPage.flatMap { pdfView.document?.index(for: $0) }
            let visiblePageIndexes = pdfView.visiblePages
                .compactMap { pdfView.document?.index(for: $0) }
                .sorted()

            parent.onReadingPositionChange(currentPageIndex, visiblePageIndexes)
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
            guard let pdfView = notification.object as? PDFView else {
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
            guard let pdfView = notification.object as? PDFView else {
                return
            }

            publishSelection(for: pdfView)
            publishReadingPosition(for: pdfView)
        }
    }
}
