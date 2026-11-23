import AppKit
import CoreaderKit
import PDFKit
import UniformTypeIdentifiers

/// Brings files and links into the library, then improves what it knows about them in
/// the background: real metadata for papers, a cover for anything that has none.
@MainActor
final class ImportService {
    private unowned let app: AppModel
    private var probe: BookProbe?

    init(app: AppModel) { self.app = app }

    static let fileTypes: [UTType] = [.pdf, .epub] + ["mobi", "azw3", "azw", "prc"].compactMap { UTType(filenameExtension: $0) }

    func chooseFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = Self.fileTypes
        panel.message = "Add books, papers and documents to your library"
        panel.prompt = "Add"
        let done: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            if response == .OK { self?.importFiles(panel.urls, openFirst: panel.urls.count == 1) }
        }
        // A sheet on the window, not an app-wide modal dialog.
        if let window = NSApp.mainWindow ?? NSApp.windows.first(where: { $0.isVisible && $0.styleMask.contains(.titled) }) {
            panel.beginSheetModal(for: window, completionHandler: done)
        } else {
            panel.begin(completionHandler: done)
        }
    }

    func importFiles(_ urls: [URL], openFirst: Bool = false) {
        Task {
            var first: BookEntry?
            var skipped = 0
            for url in urls {
                guard BookFormat(fileExtension: url.pathExtension) != nil else { skipped += 1; continue }
                if let entry = await importFile(url, metadata: ImportMetadata()) { first = first ?? entry }
            }
            if skipped > 0 { app.show("\(skipped) file\(skipped == 1 ? " is" : "s are") not a format Coreader opens (EPUB, PDF, MOBI, AZW3).", isError: true) }
            if openFirst, let first { app.open(first.id) }
        }
    }

    @discardableResult
    func importFile(_ url: URL, metadata: ImportMetadata) async -> BookEntry? {
        let library = app.library
        do {
            let known = Set(app.books.map(\.id))
            let entry = try await offMain { try library.importFile(at: url, metadata: metadata) }
            // The library folder was switched while this import ran: the book belongs to
            // the old folder and must not appear on the new shelf.
            guard app.library.root == library.root else { return nil }
            app.replace(entry)
            if known.contains(entry.id) {
                app.show("“\(entry.book.title)” is already in your library.")
                return entry
            }
            Task { await enrich(entry, sourceName: url.deletingPathExtension().lastPathComponent) }
            return entry
        } catch {
            app.show("Could not add \(url.lastPathComponent): \(error.localizedDescription)", isError: true)
            return nil
        }
    }

    /// Accepts an arXiv link or id, a DOI, or any web page URL.
    func importLink(_ input: String, selection: String? = nil) {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        Task {
            app.show("Fetching…")
            let client = PaperMetadataClient()
            if let paper = try? await client.resolve(text), paper.pdfURL != nil {
                do {
                    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
                    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                    let file = try await client.downloadPDF(paper, to: dir)
                    let meta = ImportMetadata(title: paper.title, authors: paper.authors, kind: .paper, summary: paper.abstract,
                                              publisher: paper.venue, year: paper.year,
                                              sourceURL: paper.landingURL?.absoluteString, doi: paper.doi, arxivID: paper.arxivID)
                    if let entry = await importFile(file, metadata: meta) { app.show("Added “\(entry.book.title)”.") }
                    try? FileManager.default.removeItem(at: dir)
                    return
                } catch {
                    app.show("Found the paper but could not download its PDF: \(error.localizedDescription)", isError: true)
                    return
                }
            }
            guard let url = URL(string: text), ["http", "https"].contains(url.scheme ?? "") else {
                return app.show("That does not look like a link, an arXiv id or a DOI.", isError: true)
            }
            do {
                let article = try await ArticleFetcher().fetch(url)
                let html = ArticlePackager.html(for: article)
                let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".html")
                try html.write(to: file, atomically: true, encoding: .utf8)
                let meta = ImportMetadata(title: article.title, authors: article.byline.map { [$0] } ?? [], kind: .article,
                                          summary: article.excerpt, publisher: article.siteName, sourceURL: url.absoluteString)
                if let entry = await importFile(file, metadata: meta) {
                    app.show("Saved “\(entry.book.title)”.")
                    if let selection, !selection.isEmpty {
                        let note = Annotation(kind: .highlight, quote: selection, locator: Locator(fraction: 0))
                        let notes = app.notes
                        WriteQueue.shared.enqueue(WriteQueue.notes(entry.id), { try notes.upsert(note, in: entry) })
                    }
                }
                try? FileManager.default.removeItem(at: file)
            } catch {
                app.show("Could not save that page: \(error.localizedDescription)", isError: true)
            }
        }
    }

    // MARK: Enrichment

    /// `sourceName` is the file name the book arrived with; a title equal to it is a
    /// placeholder that real metadata may replace.
    private func enrich(_ entry: BookEntry, sourceName: String) async {
        var entry = entry
        app.busyBooks[entry.id] = "Reading…"
        defer { app.busyBooks[entry.id] = nil }

        switch entry.book.format {
        case .pdf:
            entry = await enrichPDF(entry, sourceName: sourceName)
        case .epub, .mobi, .azw3:
            entry = await enrichReflowable(entry, sourceName: sourceName)
        case .article:
            if let result = await BookProbe().inspect(entry.fileURL), !result.sections.isEmpty {
                let store = app.textStore, book = entry.book, sections = result.sections
                _ = try? await offMain { try store.save(sections, for: book) }
            }
        }

        if entry.book.coverFile == nil {
            entry = await setProceduralCover(entry)
            if app.generatesCovers { await generateCover(for: entry.id) }
        }
    }

    private func enrichPDF(_ entry: BookEntry, sourceName: String) async -> BookEntry {
        let file = entry.fileURL
        let textStore = app.textStore
        let book = entry.book
        struct Facts: Sendable {
            var title: String?
            var author: String?
            var pages = 0
            var firstText = ""
            var firstPageWords = 0
            var firstPagePNG: Data?
        }
        let facts: Facts? = try? await offMain {
            guard let doc = PDFDocument(url: file) else { return nil }
            var f = Facts()
            f.pages = doc.pageCount
            let attrs = doc.documentAttributes ?? [:]
            f.title = (attrs[PDFDocumentAttribute.titleAttribute] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            f.author = (attrs[PDFDocumentAttribute.authorAttribute] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let first = doc.page(at: 0)?.string ?? ""
            f.firstPageWords = first.split(whereSeparator: \.isWhitespace).count
            f.firstText = first + "\n" + (doc.page(at: 1)?.string ?? "")
            if let page = doc.page(at: 0) {
                let image = page.thumbnail(of: NSSize(width: 900, height: 1350), for: .cropBox)
                if let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) {
                    f.firstPagePNG = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.86])
                }
            }
            // Extracted text feeds whole-book chat and the agents.
            if let sections = try? textStore.extractPDF(at: file, book: book) { try? textStore.save(sections, for: book) }
            return f
        }
        guard let facts else { return entry }

        let hints = PaperDetector.detect(firstPagesText: facts.firstText, fileName: file.lastPathComponent,
                                         pdfTitle: facts.title, pageCount: facts.pages)
        var paper: PaperMetadata?
        if hints.isLikelyPaper, entry.book.kind != .paper || entry.book.summary == nil {
            let client = PaperMetadataClient()
            if let id = hints.arxivID { paper = try? await client.lookup(arxivID: id) }
            if paper == nil, let doi = hints.doi { paper = try? await client.lookup(doi: doi) }
            if paper == nil, let title = hints.guessedTitle ?? facts.title, title.count > 12 { paper = try? await client.search(title: title) }
        }

        app.update(entry.id) { book in
            book.pageCount = facts.pages
            let untitled = Self.isPlaceholder(book.title, sourceName: sourceName, entry: entry)
            if let paper {
                if untitled || book.kind != .paper { book.title = paper.title }
                if book.authors.isEmpty { book.authors = paper.authors }
                book.summary = book.summary ?? paper.abstract
                book.year = book.year ?? paper.year
                book.publisher = book.publisher ?? paper.venue
                book.doi = book.doi ?? paper.doi
                book.arxivID = book.arxivID ?? paper.arxivID
                book.sourceURL = book.sourceURL ?? paper.landingURL?.absoluteString
            } else {
                if untitled, let t = hints.guessedTitle ?? facts.title, t.count > 3, !Self.looksLikeFileName(t) { book.title = t }
                if book.authors.isEmpty, let a = facts.author, !a.isEmpty { book.authors = a.components(separatedBy: CharacterSet(charactersIn: ",;&")).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } }
            }
            if hints.isLikelyPaper { book.kind = .paper }
        }

        // A first page with almost no text is a real cover (a scanned or designed book);
        // a page full of text is not, and gets a generated cover instead.
        if !hints.isLikelyPaper, facts.firstPageWords < 70, facts.pages > 8, let png = facts.firstPagePNG {
            await storeCover(png, fileExtension: "jpg", generated: false, for: entry.id)
        }
        return app.entry(entry.id) ?? entry
    }

    private static func isPlaceholder(_ title: String, sourceName: String, entry: BookEntry) -> Bool {
        title.isEmpty || title.caseInsensitiveCompare(sourceName) == .orderedSame
            || title == entry.folder.lastPathComponent || looksLikeFileName(title)
    }

    private static func looksLikeFileName(_ title: String) -> Bool {
        title.range(of: #"^[\w\-. ]+\.(pdf|docx?|tex|dvi|indd)$"#, options: [.regularExpression, .caseInsensitive]) != nil
            || title.range(of: #"^(untitled|microsoft word|\d{4}\.\d{4,5}(v\d+)?)"#, options: [.regularExpression, .caseInsensitive]) != nil
    }

    private func enrichReflowable(_ entry: BookEntry, sourceName: String) async -> BookEntry {
        let probe = BookProbe()
        self.probe = probe
        guard let result = await probe.inspect(entry.fileURL) else { return entry }
        self.probe = nil
        let info = result.info
        // The text feeds whole-book chat, the agents and book-to-skill from the start,
        // without the book having to be opened first.
        if !result.sections.isEmpty {
            let store = app.textStore, book = entry.book, sections = result.sections
            _ = try? await offMain { try store.save(sections, for: book) }
        }
        app.update(entry.id) { book in
            if !info.title.isEmpty, Self.isPlaceholder(book.title, sourceName: sourceName, entry: entry) { book.title = info.title }
            if book.authors.isEmpty { book.authors = info.authors }
            if book.summary == nil, !info.summary.isEmpty { book.summary = info.summary.strippingHTML }
            if book.publisher == nil, !info.publisher.isEmpty { book.publisher = info.publisher }
            if book.language == nil, !info.language.isEmpty { book.language = info.language }
            if book.year == nil, let y = Int(info.published.prefix(4)) { book.year = y }
        }
        if let cover = info.cover, !cover.isEmpty {
            await storeCover(cover, fileExtension: cover.starts(with: [0x89, 0x50]) ? "png" : "jpg", generated: false, for: entry.id)
        }
        return app.entry(entry.id) ?? entry
    }

    /// Writes the image into the book's folder, then records it through the ordered
    /// metadata writer so it cannot roll back a newer title, rating or reading position.
    private func storeCover(_ data: Data, fileExtension: String, generated: Bool, for id: String) async {
        guard let entry = app.entry(id) else { return }
        let library = app.library, folder = entry.folder, old = entry.book.coverFile
        guard let name = try? await offMain({ try library.writeCoverFile(data, fileExtension: fileExtension, in: folder, replacing: old) }) else { return }
        app.update(id) { book in
            book.coverFile = name
            book.coverIsGenerated = generated
        }
        app.coverVersion[id, default: 0] += 1
    }

    private func brief(for book: Book) -> CoverBrief { CoverBrief(book: book) }

    /// A different cover for the same book: redrawn at once with the next palette and
    /// motif, then replaced by an image model's version if one is available.
    func redesignCover(for id: String) async {
        guard let entry = app.entry(id), app.busyBooks[id] == nil else { return }
        app.update(id) { $0.coverVariant = ($0.coverVariant ?? 0) + 1 }
        _ = await setProceduralCover(entry)
        await generateCover(for: id)
    }

    private func setProceduralCover(_ entry: BookEntry) async -> BookEntry {
        guard let current = app.entry(entry.id) else { return entry }
        let svg = ProceduralCover.svg(for: brief(for: current.book), width: 800, height: 1200)
        guard let image = NSImage(data: Data(svg.utf8)), let png = image.pngData(size: NSSize(width: 800, height: 1200)) else { return current }
        await storeCover(png, fileExtension: "png", generated: true, for: entry.id)
        return app.entry(entry.id) ?? current
    }

    /// Asks an image model for a cover. Slow (minutes), so the drawn cover stays in place
    /// until this one arrives.
    func generateCover(for id: String) async {
        guard let entry = app.entry(id) else { return }
        let generator = CoverGenerator()
        guard let backend = await generator.availableBackends().first else { return }
        app.busyBooks[id] = "Designing a cover…"
        defer { app.busyBooks[id] = nil }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("coreader-cover-" + UUID().uuidString)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        do {
            let file = try await generator.generate(brief(for: entry.book), backend: backend, outputDirectory: dir)
            let data = try Data(contentsOf: file)
            guard let image = NSImage(data: data), let jpg = image.jpegData(maxDimension: 1600) else { return }
            await storeCover(jpg, fileExtension: "jpg", generated: true, for: id)
        } catch {
            DebugHooks.log("cover generation failed: \(error)")
        }
    }
}

extension String {
    var strippingHTML: String {
        replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "&amp;", with: "&").replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

extension NSImage {
    func pngData(size: NSSize) -> Data? {
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height),
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        rep.size = size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        draw(in: NSRect(origin: .zero, size: size), from: .zero, operation: .copy, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])
    }

    func jpegData(maxDimension: CGFloat) -> Data? {
        guard let cg = cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let w = CGFloat(cg.width), h = CGFloat(cg.height)
        let scale = min(1, maxDimension / max(w, h))
        let size = NSSize(width: (w * scale).rounded(), height: (h * scale).rounded())
        guard let png = pngData(size: size), let rep = NSBitmapImageRep(data: png) else { return nil }
        return rep.representation(using: .jpeg, properties: [.compressionFactor: 0.88])
    }
}

/// Reads title, authors, cover and the full text of an EPUB/MOBI/article by opening it in
/// an unseen web reader.
@MainActor
final class BookProbe {
    struct Result {
        var info: WebReaderEvent.Opened
        var sections: [BookTextStore.Section]
    }

    private var controller: WebReaderController?

    func inspect(_ file: URL) async -> Result? {
        let controller = WebReaderController()
        self.controller = controller
        defer { self.controller = nil }
        return await withCheckedContinuation { continuation in
            var finished = false
            var info: WebReaderEvent.Opened?
            var sections: [BookTextStore.Section] = []
            func finish() {
                guard !finished else { return }
                finished = true
                continuation.resume(returning: info.map { Result(info: $0, sections: sections) })
            }
            controller.onEvent = { event in
                switch event {
                case .opened(let opened):
                    info = opened
                    controller.extractText()
                case .textSection(let index, let title, let cfi, let fraction, let text):
                    sections.append(.init(index: index, title: title, locator: Locator(cfi: cfi, fraction: fraction, label: title), text: text))
                case .textDone, .openFailed:
                    finish()
                default:
                    break
                }
            }
            controller.open(file: file, lastCFI: nil, marks: [], settings: ReaderSettings().webPayload(theme: .paper))
            Task {
                // A very large book may not finish extracting in time; what there is is used.
                try? await Task.sleep(for: .seconds(60))
                finish()
            }
        }
    }
}
