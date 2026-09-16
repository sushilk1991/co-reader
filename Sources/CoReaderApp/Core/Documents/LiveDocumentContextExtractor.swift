import Foundation
import PDFKit

struct LiveDocumentContextExtractor: DocumentContextExtracting {
    private let composer = DocumentContextComposer()
    private let epubLoader: any EPUBBookLoading

    init(epubLoader: any EPUBBookLoading = LiveEPUBBookLoader()) {
        self.epubLoader = epubLoader
    }

    func extractContext(
        for document: ReaderDocument,
        question: String,
        scope: DocumentQueryScope,
        selection: DocumentSelection?,
        currentPageIndex: Int?,
        visiblePageIndexes: [Int],
        isCancelled: @escaping @Sendable () -> Bool,
        onProgress: @escaping @Sendable (PageScanProgress) -> Void
    ) throws -> DocumentContext {
        switch document.kind {
        case .pdf:
            let pageTexts = try extractPDFPageTexts(from: document.fileURL, isCancelled: isCancelled, onProgress: onProgress)
            return composer.compose(
                title: document.title,
                question: question,
                scope: scope,
                selection: selection,
                currentPageIndex: currentPageIndex,
                visiblePageIndexes: visiblePageIndexes,
                pageTexts: pageTexts
            )
        case .epub:
            let book = try epubLoader.loadBook(from: document.fileURL)
            return composer.compose(
                title: book.title,
                question: question,
                scope: scope,
                selection: selection,
                currentPageIndex: currentPageIndex,
                visiblePageIndexes: visiblePageIndexes,
                pageTexts: book.sections.map(\.textContent),
                unitLabel: "Chapter"
            )
        case .unknown:
            return DocumentContext(
                title: document.title,
                excerpt: "The document format is not yet supported for text extraction."
            )
        }
    }

    private func extractPDFPageTexts(
        from url: URL,
        isCancelled: @escaping @Sendable () -> Bool,
        onProgress: @escaping @Sendable (PageScanProgress) -> Void
    ) throws -> [String] {
        guard let pdfDocument = PDFDocument(url: url) else {
            throw NSError(
                domain: "CoReader.DocumentContext",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Unable to open PDF for context extraction."]
            )
        }

        // `page.string` runs PDFKit's text layout for the page, which is the slow part
        // of answering a question, so it is the unit of cancellation and progress.
        var pageTexts: [String] = []
        for pageIndex in 0 ..< pdfDocument.pageCount {
            guard !isCancelled() else {
                throw CancellationError()
            }

            pageTexts.append(pdfDocument.page(at: pageIndex)?.string ?? "")
            onProgress(PageScanProgress(completedPages: pageIndex + 1, totalPages: pdfDocument.pageCount))
        }

        if pageTexts.allSatisfy({ $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            return [
                "The PDF opened successfully, but no extractable text was found. Ask questions about visible diagrams or highlighted selections instead."
            ]
        }

        return pageTexts
    }
}
