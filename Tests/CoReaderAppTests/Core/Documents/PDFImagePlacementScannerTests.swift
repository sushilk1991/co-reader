import CoreGraphics
import Foundation
import PDFKit
import Testing
@testable import CoReaderApp

struct PDFImagePlacementScannerTests {
    /// A form that draws itself must not recurse until the stack overflows.
    @Test
    func selfReferencingFormIsScannedOnce() throws {
        let page = try makePage(
            pageContent: "q /Fm1 Do Q",
            forms: [
                PDFTestForm(
                    name: "Fm1",
                    matrix: "[1 0 0 1 0 0]",
                    content: "q 100 0 0 100 50 50 cm /Im1 Do Q q /Fm1 Do Q",
                    references: ["Fm1", "Im1"]
                )
            ]
        )

        let placements = PDFImagePlacementScanner().imagePlacements(for: page)

        #expect(placements.count == 1)
    }

    @Test
    func nestedFormsWithinTheDepthCapAreScanned() throws {
        let page = try makePage(
            pageContent: "q /Fm1 Do Q",
            forms: [
                PDFTestForm(name: "Fm1", matrix: "[1 0 0 1 0 0]", content: "q /Fm2 Do Q", references: ["Fm2"]),
                PDFTestForm(name: "Fm2", matrix: "[1 0 0 1 0 0]", content: "q /Fm3 Do Q", references: ["Fm3"]),
                PDFTestForm(name: "Fm3", matrix: "[1 0 0 1 0 0]", content: "q 100 0 0 100 50 50 cm /Im1 Do Q", references: ["Im1"])
            ]
        )

        #expect(PDFImagePlacementScanner().imagePlacements(for: page).count == 1)
        #expect(PDFImagePlacementScanner(maxFormDepth: 2).imagePlacements(for: page).isEmpty)
    }



    // MARK: Fixture

    private struct PDFTestForm {
        let name: String
        let matrix: String
        let content: String
        let references: [String]
    }

    /// Builds a one-page PDF by hand: object 4 is the page, 5 the image, 6+ the forms.
    private func makePage(pageContent: String, forms: [PDFTestForm]) throws -> PDFPage {
        let imageObjectNumber = 5
        let firstFormObjectNumber = 6
        var objectNumbers: [String: Int] = ["Im1": imageObjectNumber]
        for (offset, form) in forms.enumerated() {
            objectNumbers[form.name] = firstFormObjectNumber + offset
        }

        func xobjectDictionary(_ names: [String]) -> String {
            "<< " + names.map { "/\($0) \(objectNumbers[$0]!) 0 R" }.joined(separator: " ") + " >>"
        }

        var objects: [String] = [
            "<< /Type /Catalog /Pages 2 0 R >>",
            "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
            "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 300 300] /Contents 4 0 R /Resources << /XObject \(xobjectDictionary(forms.isEmpty ? ["Im1"] : [forms[0].name])) >> >>",
            stream(dictionary: "<< /Length \(pageContent.utf8.count) >>", content: pageContent),
            stream(
                dictionary: "<< /Type /XObject /Subtype /Image /Width 1 /Height 1 /ColorSpace /DeviceGray /BitsPerComponent 8 /Length 1 >>",
                content: "\u{0}"
            )
        ]
        for form in forms {
            objects.append(
                stream(
                    dictionary: "<< /Type /XObject /Subtype /Form /BBox [0 0 300 300] /Matrix \(form.matrix) /Resources << /XObject \(xobjectDictionary(form.references)) >> /Length \(form.content.utf8.count) >>",
                    content: form.content
                )
            )
        }

        var body = "%PDF-1.4\n"
        var offsets: [Int] = []
        for (index, object) in objects.enumerated() {
            offsets.append(body.utf8.count)
            body += "\(index + 1) 0 obj\n\(object)\nendobj\n"
        }
        let xrefOffset = body.utf8.count
        body += "xref\n0 \(objects.count + 1)\n0000000000 65535 f \n"
        for offset in offsets {
            body += String(format: "%010d 00000 n \n", offset)
        }
        body += "trailer\n<< /Size \(objects.count + 1) /Root 1 0 R >>\nstartxref\n\(xrefOffset)\n%%EOF\n"

        let document = try #require(PDFDocument(data: Data(body.utf8)))
        return try #require(document.page(at: 0))
    }

    private func stream(dictionary: String, content: String) -> String {
        "\(dictionary)\nstream\n\(content)\nendstream"
    }
}
