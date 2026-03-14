import CoreGraphics
import Testing
@testable import CoReaderApp

struct PDFDocumentHighlightTests {
    @Test
    func highlightRectProducesAbsoluteQuadrilateralPoints() {
        let rect = PDFDocumentHighlight.HighlightRect(
            rect: CGRect(x: 32, y: 144, width: 220, height: 18)
        )

        #expect(
            rect.quadrilateralPoints == [
                CGPoint(x: 32, y: 162),
                CGPoint(x: 252, y: 162),
                CGPoint(x: 32, y: 144),
                CGPoint(x: 252, y: 144)
            ]
        )
    }
}
