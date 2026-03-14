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
        selection: DocumentSelection?,
        currentPageIndex: Int?,
        visiblePageIndexes: [Int]
    ) throws -> DocumentContext {
        switch document.kind {
        case .pdf:
            let pageTexts = try extractPDFPageTexts(from: document.fileURL)
            return composer.compose(
                title: document.title,
                question: question,
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

    private func extractPDFPageTexts(from url: URL) throws -> [String] {
        guard let pdfDocument = PDFDocument(url: url) else {
            throw NSError(
                domain: "CoReader.DocumentContext",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Unable to open PDF for context extraction."]
            )
        }

        let pageTexts = (0 ..< pdfDocument.pageCount).map { pageIndex in
            pdfDocument.page(at: pageIndex)?.string ?? ""
        }

        if pageTexts.allSatisfy({ $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            return [
                "The PDF opened successfully, but no extractable text was found. Ask questions about visible diagrams or highlighted selections instead."
            ]
        }

        return pageTexts
    }
}
