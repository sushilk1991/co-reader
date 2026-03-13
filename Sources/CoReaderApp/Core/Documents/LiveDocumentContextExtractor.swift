import Foundation
import PDFKit

struct LiveDocumentContextExtractor: DocumentContextExtracting {
    func extractContext(for document: ReaderDocument) throws -> DocumentContext {
        switch document.kind {
        case .pdf:
            let excerpt = try extractPDFExcerpt(from: document.fileURL)
            return DocumentContext(title: document.title, excerpt: excerpt)
        case .epub:
            return DocumentContext(
                title: document.title,
                excerpt: "EPUB support is imported into the workspace. Full text extraction is the next document-engine checkpoint."
            )
        case .unknown:
            return DocumentContext(
                title: document.title,
                excerpt: "The document format is not yet supported for text extraction."
            )
        }
    }

    private func extractPDFExcerpt(from url: URL) throws -> String {
        guard let pdfDocument = PDFDocument(url: url) else {
            throw NSError(
                domain: "CoReader.DocumentContext",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Unable to open PDF for context extraction."]
            )
        }

        let rawText = pdfDocument.string?
            .replacingOccurrences(of: "\u{0}", with: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        let excerpt = String(rawText.prefix(8_000))
        if excerpt.isEmpty {
            return "The PDF opened successfully, but no extractable text was found. Ask questions about visible diagrams or highlighted selections instead."
        }

        return excerpt
    }
}
