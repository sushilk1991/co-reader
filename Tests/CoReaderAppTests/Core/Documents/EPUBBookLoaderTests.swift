import Foundation
import Testing
@testable import CoReaderApp

struct EPUBBookLoaderTests {
    @Test
    func parserResolvesPackagePathFromContainerXML() throws {
        let parser = EPUBPackageParser()

        let path = try parser.packagePath(
            from: Data(
                """
                <?xml version="1.0" encoding="UTF-8"?>
                <container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
                  <rootfiles>
                    <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
                  </rootfiles>
                </container>
                """.utf8
            )
        )

        #expect(path == "OEBPS/content.opf")
    }

    @Test
    func parserBuildsOrderedSectionsFromExtractedEPUBDirectory() throws {
        let fixture = try EPUBFixture.make()
        let parser = EPUBPackageParser()

        let book = try parser.makeBook(
            extractedRootURL: fixture.extractedRootURL,
            fallbackTitle: "Fallback Title"
        )

        #expect(book.title == "Sample EPUB")
        #expect(book.sections.count == 2)
        #expect(book.sections.map(\.title) == ["Introduction", "Agent Mesh"])
        #expect(book.sections.map { $0.contentURL.lastPathComponent } == ["chapter-1.xhtml", "chapter-2.xhtml"])
        #expect(book.sections[1].textContent.contains("Agents coordinate through a shared protocol."))
    }

    @Test
    func loaderExtractsBookFromEPUBArchive() throws {
        let fixture = try EPUBFixture.make()
        let cacheDirectory = fixture.workingDirectory.appending(path: "Cache", directoryHint: .isDirectory)
        let loader = LiveEPUBBookLoader(cacheDirectory: cacheDirectory)

        let book = try loader.loadBook(from: fixture.archiveURL)

        #expect(book.title == "Sample EPUB")
        #expect(book.sections.count == 2)
        #expect(book.sections.first?.title == "Introduction")
        #expect(book.sections.last?.textContent.contains("Agents coordinate through a shared protocol.") == true)
    }

    @Test
    func parserReadsPercentEncodedSectionPaths() throws {
        let fixture = try EPUBFixture.make(
            chapter1Filename: "Chapter 1.xhtml",
            chapter1Href: "Chapter%201.xhtml"
        )
        let parser = EPUBPackageParser()

        let book = try parser.makeBook(
            extractedRootURL: fixture.extractedRootURL,
            fallbackTitle: "Fallback Title"
        )

        #expect(book.sections.first?.contentURL.lastPathComponent == "Chapter 1.xhtml")
        #expect(book.sections.first?.title == "Introduction")
    }

    @Test
    func parserPreservesNonUTF8ChapterText() throws {
        let fixture = try EPUBFixture.make(
            chapter1Filename: "chapter-1.xhtml",
            chapter1Href: "chapter-1.xhtml",
            chapter1Title: "Caf\u{00E9}",
            chapter1Paragraph: "A na\u{00EF}ve fa\u{00E7}ade should stay readable.",
            chapter1Encoding: .windowsCP1252
        )
        let parser = EPUBPackageParser()

        let book = try parser.makeBook(
            extractedRootURL: fixture.extractedRootURL,
            fallbackTitle: "Fallback Title"
        )

        #expect(book.sections.first?.title == "Caf\u{00E9}")
        #expect(book.sections.first?.textContent.contains("A na\u{00EF}ve fa\u{00E7}ade should stay readable.") == true)
    }

    @Test
    func bookResolvesSectionIndexForNavigatedFileURLs() {
        let chapter1URL = URL(fileURLWithPath: "/tmp/Book/chapter-1.xhtml")
        let chapter2URL = URL(fileURLWithPath: "/tmp/Book/chapter-2.xhtml")
        let book = EPUBBook(
            title: "Sample EPUB",
            rootURL: URL(fileURLWithPath: "/tmp/Book"),
            sections: [
                EPUBSection(id: "one", title: "One", contentURL: chapter1URL, textContent: "One"),
                EPUBSection(id: "two", title: "Two", contentURL: chapter2URL, textContent: "Two")
            ]
        )
        let navigatedURL = URL(string: "file:///tmp/Book/chapter-2.xhtml#footnote-1")!

        #expect(book.sectionIndex(for: navigatedURL) == 1)
    }
}

private struct EPUBFixture {
    let workingDirectory: URL
    let extractedRootURL: URL
    let archiveURL: URL

    static func make(
        chapter1Filename: String = "chapter-1.xhtml",
        chapter1Href: String = "chapter-1.xhtml",
        chapter1Title: String = "Introduction",
        chapter1Paragraph: String = "EPUB reading should feel native on macOS.",
        chapter1Encoding: String.Encoding = .utf8
    ) throws -> Self {
        let workingDirectory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let extractedRootURL = workingDirectory.appending(path: "Book", directoryHint: .isDirectory)
        let metaInfURL = extractedRootURL.appending(path: "META-INF", directoryHint: .isDirectory)
        let oebpsURL = extractedRootURL.appending(path: "OEBPS", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: metaInfURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: oebpsURL, withIntermediateDirectories: true)

        try Data(
            """
            <?xml version="1.0" encoding="UTF-8"?>
            <container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
              <rootfiles>
                <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
              </rootfiles>
            </container>
            """.utf8
        ).write(to: metaInfURL.appending(path: "container.xml"))

        try Data(
            """
            <?xml version="1.0" encoding="UTF-8"?>
            <package version="3.0" xmlns="http://www.idpf.org/2007/opf">
              <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
                <dc:title>Sample EPUB</dc:title>
              </metadata>
              <manifest>
                <item id="chapter-1" href="\(chapter1Href)" media-type="application/xhtml+xml"/>
                <item id="chapter-2" href="chapter-2.xhtml" media-type="application/xhtml+xml"/>
              </manifest>
              <spine>
                <itemref idref="chapter-1"/>
                <itemref idref="chapter-2"/>
              </spine>
            </package>
            """.utf8
        ).write(to: oebpsURL.appending(path: "content.opf"))

        let chapter1Document = """
        <?xml version="1.0" encoding="\(xmlEncodingName(for: chapter1Encoding))"?>
        <html xmlns="http://www.w3.org/1999/xhtml">
          <head><title>\(chapter1Title)</title></head>
          <body>
            <h1>\(chapter1Title)</h1>
            <p>\(chapter1Paragraph)</p>
          </body>
        </html>
        """
        try encodedData(for: chapter1Document, encoding: chapter1Encoding)
            .write(to: oebpsURL.appending(path: chapter1Filename))

        try Data(
            """
            <?xml version="1.0" encoding="UTF-8"?>
            <html xmlns="http://www.w3.org/1999/xhtml">
              <head><title>Agent Mesh</title></head>
              <body>
                <h1>Agent Mesh</h1>
                <p>Agents coordinate through a shared protocol.</p>
              </body>
            </html>
            """.utf8
        ).write(to: oebpsURL.appending(path: "chapter-2.xhtml"))

        let archiveURL = workingDirectory.appending(path: "Sample.epub")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.arguments = ["-qr", archiveURL.path, "."]
        process.currentDirectoryURL = extractedRootURL
        try process.run()
        process.waitUntilExit()

        #expect(process.terminationStatus == 0)

        return Self(
            workingDirectory: workingDirectory,
            extractedRootURL: extractedRootURL,
            archiveURL: archiveURL
        )
    }
}

private func encodedData(for value: String, encoding: String.Encoding) throws -> Data {
    guard let data = value.data(using: encoding) else {
        throw NSError(
            domain: "CoReader.EPUBFixture",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Unable to encode EPUB fixture data."]
        )
    }

    return data
}

private func xmlEncodingName(for encoding: String.Encoding) -> String {
    switch encoding {
    case .utf8:
        "UTF-8"
    case .windowsCP1252:
        "windows-1252"
    default:
        "UTF-8"
    }
}
