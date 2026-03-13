import Foundation
import Testing
@testable import CoReaderApp

struct DocumentLibraryTests {
    @Test
    func importDocumentRecognizesPDFAndPreventsDuplicates() {
        var library = DocumentLibrary()
        let url = URL(fileURLWithPath: "/tmp/Swift Systems Design.pdf")

        let firstImport = library.importDocument(at: url)
        let secondImport = library.importDocument(at: url)

        #expect(firstImport.kind == .pdf)
        #expect(firstImport.title == "Swift Systems Design")
        #expect(secondImport.id == firstImport.id)
        #expect(library.documents.count == 1)
    }

    @Test
    func importDocumentRecognizesEPUBByExtension() {
        var library = DocumentLibrary()
        let url = URL(fileURLWithPath: "/tmp/Distributed Reading.epub")

        let document = library.importDocument(at: url)

        #expect(document.kind == .epub)
        #expect(document.title == "Distributed Reading")
        #expect(library.documents.first?.fileURL == url)
    }
}
