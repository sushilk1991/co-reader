import Foundation
import PDFKit
import Testing
@testable import CoReaderApp

@MainActor
struct HighlightingPDFViewTests {
    /// Re-syncing an unchanged highlight list must leave the existing annotations in
    /// place; stripping and re-adding them on every SwiftUI update is what caused
    /// PDFKit flicker and hangs while scrolling.
    @Test
    func syncingUnchangedHighlightsKeepsExistingAnnotations() throws {
        let document = PDFDocument()
        document.insert(PDFPage(), at: 0)
        let view = HighlightingPDFView()
        view.document = document
        let page = try #require(document.page(at: 0))
        let first = makeHighlight(id: "AAAAAAAA-0000-0000-0000-000000000001", text: "First")
        let second = makeHighlight(id: "AAAAAAAA-0000-0000-0000-000000000002", text: "Second")

        view.syncManagedHighlights([first, second])
        let installed = Set(page.annotations.map(ObjectIdentifier.init))

        view.syncManagedHighlights([first, second])

        #expect(page.annotations.count == 2)
        #expect(Set(page.annotations.map(ObjectIdentifier.init)) == installed)
    }

    @Test
    func syncingRemovesOnlyTheHighlightsThatWentAway() throws {
        let document = PDFDocument()
        document.insert(PDFPage(), at: 0)
        let view = HighlightingPDFView()
        view.document = document
        let page = try #require(document.page(at: 0))
        let first = makeHighlight(id: "AAAAAAAA-0000-0000-0000-000000000001", text: "First")
        let second = makeHighlight(id: "AAAAAAAA-0000-0000-0000-000000000002", text: "Second")

        view.syncManagedHighlights([first, second])
        let firstAnnotation = try #require(page.annotations.first { $0.contents == "First" })

        view.syncManagedHighlights([first])

        #expect(page.annotations.count == 1)
        #expect(page.annotations.first === firstAnnotation)
    }

    private func makeHighlight(id: String, text: String) -> PDFDocumentHighlight {
        PDFDocumentHighlight(
            id: UUID(uuidString: id)!,
            pageIndex: 0,
            quotedText: text,
            noteText: nil,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            color: .yellow,
            rects: [PDFDocumentHighlight.HighlightRect(rect: CGRect(x: 40, y: 500, width: 180, height: 18))]
        )
    }
}
