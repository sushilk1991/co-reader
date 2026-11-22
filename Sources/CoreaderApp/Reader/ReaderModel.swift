import AppKit
import CoreaderKit
import SwiftUI
import WebKit

/// The passage currently selected in the book, whatever the format.
struct ReaderSelection: Equatable {
    var text: String
    /// The paragraph around the selection, for the AI.
    var context: String
    var locator: Locator
    var chapter: String
    /// Selection bounds in the reading area's coordinates (top-left origin).
    var rect: CGRect
}

enum ReaderPanel: String, Identifiable {
    case notes, chat
    var id: String { rawValue }
}

/// A quick AI answer shown beside the selection, without opening the chat.
struct Glance: Identifiable, Equatable {
    enum Kind: String { case explain = "Explain", define = "Define", translate = "Translate" }
    let id = UUID()
    var kind: Kind
    var selection: ReaderSelection
    var answer = ""
    var isLoading = true
    var failed = false
}

/// One user edit to an annotation, small enough to replay onto the copy in the file.
enum AnnotationEdit: Sendable {
    case color(HighlightColor)
    case note(String)

    func apply(to annotation: inout Annotation) {
        switch self {
        case .color(let color): annotation.color = color
        case .note(let text): annotation.note = text
        }
    }
}

/// A citation the reader clicked in a paper, with the cited work once it is found.
struct CitationLookup: Identifiable, Equatable {
    let id = UUID()
    var entry: String
    var rect: CGRect
    var paper: PaperMetadata?
    var isLoading = true
}

struct SearchHit: Identifiable {
    let id = UUID()
    var locator: Locator
    var before: String
    var match: String
    var after: String
    var section: String
}

/// State and behaviour of one open book.
@MainActor
@Observable
final class ReaderModel {
    private(set) var entry: BookEntry
    @ObservationIgnored unowned let app: AppModel

    let web: WebReaderController?
    let pdf: PDFReaderController?
    let chat: ChatModel

    var annotations: [Annotation] = []
    var toc: [TOCItem] = []
    var isLoading = true
    var loadError: String?

    var fraction: Double
    var chapter = ""
    var pageLabel = ""
    var currentLocator: Locator
    /// Text visible on the current page(s): "ask about this page".
    var visibleText = ""

    var selection: ReaderSelection?
    var glance: Glance? {
        // Dismissing a quick answer stops the agent that was still writing it.
        didSet { if glance == nil { glanceTask?.cancel() } }
    }
    @ObservationIgnored private var glanceTask: Task<Void, Never>?
    var citation: CitationLookup?
    /// Highlights from other books that resemble the page in view.
    var echoes: [RelatedFinder.Match] = []
    var showsWelcomeBack = false
    let openedAt = Date()
    /// Annotation whose note is being edited in the popover on the page.
    var activeAnnotation: ActiveAnnotation?

    var panel: ReaderPanel? {
        didSet {
            UserDefaults.standard.set(panel?.rawValue, forKey: "reader.panel")
            if panel == .notes { refreshEchoes() }
        }
    }
    var showsContents = false
    var showsAppearance = false
    var showsSearch = false
    var isChromeVisible = true
    var isFocusMode = false
    var isSnipping = false
    var showsFinishCard = false

    var searchQuery = ""
    var searchHits: [SearchHit] = []
    var isSearching = false

    /// Drives the page-turn animation: an image of the page being left.
    var turn: TurningPage?

    struct ActiveAnnotation: Identifiable, Equatable {
        var id: String
        var rect: CGRect
    }

    struct TurningPage: Identifiable {
        let id = UUID()
        var image: NSImage
        var forward: Bool
    }

    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var clock: Task<Void, Never>?
    @ObservationIgnored private var textSections: [BookTextStore.Section] = []
    @ObservationIgnored private var pendingLink: DeepLink?
    @ObservationIgnored private var didPromptFinish = false

    init(entry: BookEntry, app: AppModel) {
        self.entry = entry
        self.app = app
        let progress = entry.book.progress.isFinite ? min(max(entry.book.progress, 0), 1) : 0
        fraction = progress
        currentLocator = entry.book.location ?? Locator(fraction: progress)
        panel = UserDefaults.standard.string(forKey: "reader.panel").flatMap(ReaderPanel.init(rawValue:))
        chat = ChatModel()
        if entry.book.format == .pdf {
            pdf = PDFReaderController()
            web = nil
        } else {
            web = WebReaderController()
            pdf = nil
        }
        chat.reader = self
        start()
    }

    var book: Book { app.entry(entry.id)?.book ?? entry.book }
    var palette: Palette { app.palette }

    // MARK: Opening

    private func start() {
        // Back after a few days away: offer a recap before reading on.
        if let last = entry.book.lastOpenedAt, Date().timeIntervalSince(last) > 3 * 86_400,
           entry.book.progress > 0.05, entry.book.progress < 0.97 {
            showsWelcomeBack = true
        }
        app.update(entry.id) { book in
            book.lastOpenedAt = Date()
            if book.status == .toRead { book.status = .reading }
        }
        let notes = app.notes
        let entry = entry
        Task {
            do {
                // The book and its notes may be iCloud placeholders on this Mac.
                try await CloudFile.ensureLocal(entry.fileURL)
                if FileManager.default.fileExists(atPath: entry.notesURL.path) || !CloudFile.isLocal(entry.notesURL) {
                    try await CloudFile.ensureLocal(entry.notesURL)
                }
            } catch {
                isLoading = false
                loadError = error.localizedDescription
                return
            }
            annotations = (try? await offMain { try notes.load(entry) }) ?? []
            openDocument()
        }
        clock = Task { [weak self] in
            // Reading time counts only while the app is frontmost with this book open.
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(15))
                guard let self, NSApp.isActive, self.app.reader === self else { continue }
                self.app.update(self.entry.id) { $0.secondsRead += 15 }
                self.app.review.recordReading(seconds: 15, bookID: self.entry.id)
            }
        }
    }

    private func openDocument() {
        let settings = app.settings
        // A link that opened this book decides where it opens; restoring the saved place
        // first and jumping afterwards would race.
        var start = entry.book.location
        if let link = pendingLink {
            switch link {
            case .book: break
            case .location(_, let locator): start = locator
            case .annotation(_, let id): start = annotations.first { $0.id == id }?.locator ?? start
            }
            if start?.cfi != nil || start?.page != nil { pendingLink = nil }
        }
        if let web {
            web.onEvent = { [weak self] in self?.handle($0) }
            let marks = annotations.compactMap(mark(for:))
            web.open(file: entry.fileURL, lastCFI: start?.cfi, marks: marks, settings: webSettings)
        } else if let pdf {
            pdf.onEvent = { [weak self] in self?.handle($0) }
            pdf.open(file: entry.fileURL, page: start?.page ?? 0, annotations: annotations,
                     settings: settings, theme: app.theme)
        }
    }

    /// Saved articles always take the reading typeface: their own styling is the web's.
    private var webSettings: [String: Any] {
        var payload = app.settings.webPayload(theme: app.theme)
        if entry.book.format == .article { payload["overrideFonts"] = true }
        return payload
    }

    func close() {
        clock?.cancel()
        saveTask?.cancel()
        persistLocation()
        chat.stop()
        glanceTask?.cancel()
        echoTask?.cancel()
        pdf?.dispose()
    }

    func settingsChanged() {
        web?.apply(settings: webSettings)
        pdf?.apply(settings: app.settings, theme: app.theme)
    }

    private func mark(for a: Annotation) -> WebReaderController.AnnotationMark? {
        guard a.kind != .image, let cfi = a.locator.cfi, !a.quote.isEmpty else { return nil }
        return .init(id: a.id, cfi: cfi, color: a.color, hasNote: !a.note.isEmpty)
    }

    // MARK: Events

    private func handle(_ event: WebReaderEvent) {
        switch event {
        case .ready:
            break
        case .opened(let info):
            toc = info.toc
            isLoading = false
            if !app.textStore.hasText(for: entry.id) {
                textSections = []
                web?.extractText()
            }
            if let link = pendingLink { pendingLink = nil; follow(link) }
        case .openFailed(let message):
            isLoading = false
            loadError = message
        case .relocated(let r):
            let label = r.page.isEmpty ? r.chapter : "p. \(r.page)"
            relocated(Locator(cfi: r.cfi, fraction: r.fraction, label: label.isEmpty ? nil : label),
                      chapter: r.chapter, pageLabel: r.page.isEmpty ? "" : "Page \(r.page)", visible: r.visibleText)
        case .selection(let s):
            glance = nil
            activeAnnotation = nil
            let label = pageLabel.isEmpty ? s.chapter : pageLabel.replacingOccurrences(of: "Page ", with: "p. ")
            selection = ReaderSelection(text: s.text, context: s.context,
                                        locator: Locator(cfi: s.cfi, fraction: s.fraction, label: label.isEmpty ? nil : label),
                                        chapter: s.chapter, rect: s.rect)
        case .selectionCleared:
            selection = nil
        case .annotationTapped(let id, let rect):
            selection = nil
            activeAnnotation = .init(id: id, rect: rect)
        case .imageContext(let image):
            showImageMenu(image)
        case .imageOpen(let image):
            saveImage(image.data, fileExtension: image.fileExtension, caption: image.caption,
                      locator: Locator(cfi: image.cfi, fraction: image.fraction, label: image.chapter), chapter: image.chapter)
        case .contextMenu(let point, let hasSelection):
            showContextMenu(at: point, hasSelection: hasSelection)
        case .tap(let x):
            if activeAnnotation != nil || glance != nil { activeAnnotation = nil; glance = nil; return }
            if x < 0.22 { previousPage() } else if x > 0.78 { nextPage() } else if isFocusMode {
                withAnimation(.easeInOut(duration: 0.2)) { isChromeVisible.toggle() }
            }
        case .externalLink(let url):
            openExternal(url)
        case .textSection(let index, let title, let cfi, let fraction, let text):
            textSections.append(.init(index: index, title: title, locator: Locator(cfi: cfi, fraction: fraction, label: title), text: text))
        case .textDone:
            let sections = textSections, book = book, store = app.textStore
            textSections = []
            Task { try? await offMain { try store.save(sections, for: book) } }
        case .searchResults(let hits):
            searchHits += hits.map { SearchHit(locator: Locator(cfi: $0.cfi), before: $0.pre, match: $0.match, after: $0.post, section: $0.section) }
        case .searchDone:
            isSearching = false
        case .escape:
            escape()
        }
    }

    private func handle(_ event: PDFReaderEvent) {
        switch event {
        case .opened(let toc, _):
            self.toc = toc
            isLoading = false
            if let link = pendingLink { pendingLink = nil; follow(link) }
        case .openFailed(let message):
            isLoading = false
            loadError = message
        case .relocated(let page, let count, let chapter, let visible):
            relocated(Locator(page: page, fraction: count > 1 ? Double(page) / Double(count - 1) : 1, label: "p. \(page + 1)"),
                      chapter: chapter, pageLabel: "Page \(page + 1) of \(count)", visible: visible)
        case .selection(let s):
            glance = nil
            activeAnnotation = nil
            selection = s
        case .selectionCleared:
            selection = nil
        case .annotationTapped(let id, let rect):
            selection = nil
            activeAnnotation = .init(id: id, rect: rect)
        case .contextMenu(let point, let hasSelection):
            showContextMenu(at: point, hasSelection: hasSelection)
        case .tap:
            if activeAnnotation != nil || glance != nil { activeAnnotation = nil; glance = nil }
        case .link(let url):
            openExternal(url)
        case .citation(let entry, let rect):
            lookUpCitation(entry, rect: rect)
        }
    }

    /// Links inside books are untrusted: only web and mail links leave the app, and only
    /// Coreader's own links are followed inside it. File and other app schemes are ignored.
    private func openExternal(_ url: URL) {
        switch url.scheme?.lowercased() {
        case DeepLink.scheme: app.handle(url: url)
        case "http", "https", "mailto": NSWorkspace.shared.open(url)
        default: break
        }
    }

    // MARK: Citations

    private func lookUpCitation(_ entry: String, rect: CGRect) {
        selection = nil
        glance = nil
        activeAnnotation = nil
        let lookup = CitationLookup(entry: entry, rect: rect)
        citation = lookup
        let parsed = ReferenceParser.parse(referencesText: "[1] " + entry).first
        Task {
            let client = PaperMetadataClient()
            var paper: PaperMetadata?
            if let id = parsed?.arxivID { paper = try? await client.lookup(arxivID: id) }
            if paper == nil, let doi = parsed?.doi { paper = try? await client.lookup(doi: doi) }
            if paper == nil, let title = parsed?.title, title.count > 10 { paper = try? await client.search(title: title) }
            guard citation?.id == lookup.id else { return }
            citation?.paper = paper
            citation?.isLoading = false
        }
    }

    func addCitedPaper() {
        guard let paper = citation?.paper else { return }
        let link = paper.arxivID ?? paper.doi ?? paper.landingURL?.absoluteString
        citation = nil
        if let link { app.importer.importLink(link) }
    }

    // MARK: Echoes

    @ObservationIgnored private var echoTask: Task<Void, Never>?
    @ObservationIgnored private var otherBooks: [GraphInput]?

    /// Finds highlights in other books that resemble the visible page. Runs only while the
    /// notes panel is open, a moment after the page settles.
    func refreshEchoes() {
        echoTask?.cancel()
        guard panel == .notes, visibleText.count > 200 else { echoes = []; return }
        let text = String(visibleText.prefix(1400)), bookID = entry.id
        let library = app.library, notes = app.notes
        let known = otherBooks
        echoTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.2))
            guard !Task.isCancelled else { return }
            struct Found: Sendable { var inputs: [GraphInput]; var matches: [RelatedFinder.Match] }
            let found: Found? = try? await offMain {
                var inputs = known
                if inputs == nil {
                    var byBook: [String: (Book, [Annotation])] = [:]
                    for pair in try notes.all(in: library) where pair.entry.id != bookID && pair.annotation.kind == .highlight && pair.annotation.quote.count > 30 {
                        byBook[pair.entry.id, default: (pair.entry.book, [])].1.append(pair.annotation)
                    }
                    inputs = byBook.values.map { GraphInput(book: $0.0, annotations: $0.1) }
                }
                let matches = RelatedFinder().related(to: text, among: inputs ?? [], excludingBookID: bookID, limit: 3, minimumScore: 0.55)
                return Found(inputs: inputs ?? [], matches: matches)
            }
            guard !Task.isCancelled, let self, let found else { return }
            self.otherBooks = found.inputs
            self.echoes = found.matches
        }
    }

    private func relocated(_ locator: Locator, chapter: String, pageLabel: String, visible: String) {
        currentLocator = locator
        fraction = locator.fraction
        self.chapter = chapter
        self.pageLabel = pageLabel
        visibleText = visible
        activeAnnotation = nil
        citation = nil
        refreshEchoes()
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.2))
            guard !Task.isCancelled else { return }
            self?.persistLocation()
        }
        if fraction >= 0.985, book.status != .read, !didPromptFinish {
            didPromptFinish = true
            withAnimation(.spring(duration: 0.4)) { showsFinishCard = true }
        }
    }

    private func persistLocation() {
        let locator = currentLocator, fraction = fraction
        guard !isLoading, loadError == nil else { return }
        app.update(entry.id) { book in
            book.location = locator
            book.progress = fraction
        }
    }

    // MARK: Navigation

    func nextPage() { turnPage(forward: true) }
    func previousPage() { turnPage(forward: false) }

    private func turnPage(forward: Bool) {
        selection = nil
        glance = nil
        guard let web else {
            forward ? pdf?.next() : pdf?.previous()
            return
        }
        guard app.settings.pageTurn == .turn, turn == nil, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            forward ? web.next() : web.previous()
            return
        }
        // Photograph the page being left, move underneath, then animate the photo away.
        // The page must turn even if the photograph never arrives, so a short deadline
        // turns it plainly; whichever comes first wins.
        var turned = false
        let advance: (NSImage?) -> Void = { [weak self] image in
            guard !turned else { return }
            turned = true
            if let image { self?.turn = TurningPage(image: image, forward: forward) }
            forward ? web.next() : web.previous()
        }
        web.webView.takeSnapshot(with: nil) { image, _ in
            MainActor.assumeIsolated { advance(image) }
        }
        Task {
            try? await Task.sleep(for: .milliseconds(180))
            advance(nil)
        }
    }

    func go(to item: TOCItem) {
        showsContents = false
        if let web { web.go(toHref: item.href) } else if let page = Int(item.href) { pdf?.go(toPage: page) }
    }

    func go(to locator: Locator) {
        if let cfi = locator.cfi, let web { web.go(toCFI: cfi) }
        else if let page = locator.page, let pdf { pdf.go(toPage: page) }
        else if let web { web.go(toFraction: locator.fraction) }
        else if let pdf { pdf.go(toFraction: locator.fraction) }
    }

    func go(toFraction f: Double) {
        guard f.isFinite else { return }
        if let web { web.go(toFraction: f) } else { pdf?.go(toFraction: f) }
    }

    func follow(_ link: DeepLink) {
        guard !isLoading else { pendingLink = link; return }
        switch link {
        case .book: break
        case .location(_, let locator): go(to: locator)
        case .annotation(_, let id): show(annotationID: id)
        }
    }

    func show(annotationID id: String) {
        guard let a = annotations.first(where: { $0.id == id }) else { return }
        go(to: a.locator)
    }

    func escape() {
        if isSnipping { isSnipping = false }
        else if citation != nil { citation = nil }
        else if glance != nil { glance = nil }
        else if activeAnnotation != nil { activeAnnotation = nil }
        else if selection != nil { clearSelection() }
        else if showsSearch { showsSearch = false }
        else if isFocusMode { toggleFocus() }
    }

    func clearSelection() {
        web?.clearSelection()
        pdf?.clearSelection()
        selection = nil
    }

    func toggleFocus() {
        withAnimation(.easeInOut(duration: 0.3)) {
            isFocusMode.toggle()
            isChromeVisible = !isFocusMode
            if isFocusMode { panel = nil }
        }
    }

    // MARK: Search

    func runSearch() {
        let query = searchQuery.trimmingCharacters(in: .whitespaces)
        searchHits = []
        guard query.count >= 2 else { web?.clearSearch(); isSearching = false; return }
        isSearching = true
        if let web { web.search(query) }
        else if let pdf {
            Task {
                searchHits = await pdf.search(query)
                isSearching = false
            }
        }
    }

    func endSearch() {
        showsSearch = false
        searchQuery = ""
        searchHits = []
        web?.clearSearch()
        pdf?.clearSearch()
    }

    // MARK: Annotations

    /// Highlights the current selection. Returns the new annotation.
    @discardableResult
    func highlight(_ color: HighlightColor, note: String = "") -> Annotation? {
        guard let s = selection else { return nil }
        UserDefaults.standard.set(color.rawValue, forKey: "highlight.lastColor")
        // The same passage highlighted again changes its colour; two marks on one range
        // could not be told apart on the page.
        if let cfi = s.locator.cfi, let existing = annotations.first(where: { $0.kind == .highlight && $0.locator.cfi == cfi }) {
            update(existing.id, .color(color))
            if !note.isEmpty { update(existing.id, .note(note)) }
            web?.clearSelection()
            selection = nil
            return annotations.first { $0.id == existing.id }
        }
        let annotation = Annotation(kind: .highlight, quote: s.text.collapsingWhitespace, note: note, color: color,
                                    locator: s.locator, chapter: s.chapter.isEmpty ? nil : s.chapter)
        annotations.append(annotation)
        sortAnnotations()
        if let mark = mark(for: annotation) { web?.add(mark) }
        pdf?.add(annotation)
        pdf?.clearSelection()
        selection = nil
        save(annotation)
        return annotation
    }

    var lastColor: HighlightColor {
        UserDefaults.standard.string(forKey: "highlight.lastColor").flatMap(HighlightColor.init(rawValue:)) ?? .yellow
    }

    /// Highlights the selection and opens its note for typing.
    func noteOnSelection() {
        guard let rect = selection?.rect, let a = highlight(lastColor) else { return }
        activeAnnotation = .init(id: a.id, rect: rect)
    }

    /// Changes one field of an annotation. The change is applied to the annotation as it
    /// is in the file at write time, so text edited elsewhere since the book was opened
    /// is not overwritten by the copy in memory.
    func update(_ id: String, _ edit: AnnotationEdit) {
        guard let index = annotations.firstIndex(where: { $0.id == id }) else { return }
        edit.apply(to: &annotations[index])
        let a = annotations[index]
        if let mark = mark(for: a) { web?.update(mark) }
        pdf?.update(a)
        let notes = app.notes, entry = entry
        WriteQueue.shared.enqueue(WriteQueue.notes(entry.id), {
            // Missing from the file (not yet written, or removed by hand): write it whole.
            if try notes.update(id: id, in: entry, { edit.apply(to: &$0) }) == nil { try notes.upsert(a, in: entry) }
        }, onError: writeFailed)
    }

    func remove(_ id: String) {
        guard let index = annotations.firstIndex(where: { $0.id == id }) else { return }
        annotations.remove(at: index)
        if activeAnnotation?.id == id { activeAnnotation = nil }
        web?.removeAnnotation(id: id)
        pdf?.remove(id: id)
        let notes = app.notes, entry = entry
        WriteQueue.shared.enqueue(WriteQueue.notes(entry.id), { try notes.remove(id: id, from: entry) }, onError: writeFailed)
    }

    private func writeFailed(_ error: Error) {
        app.show("Could not write to the notes file: \(error.localizedDescription)", isError: true)
    }

    /// Adds a free-standing note at the current place (or stores an AI answer).
    func addNote(_ text: String, quote: String = "") {
        let a = Annotation(kind: quote.isEmpty ? .note : .highlight, quote: quote, note: text, color: lastColor,
                           locator: currentLocator, chapter: chapter.isEmpty ? nil : chapter)
        annotations.append(a)
        sortAnnotations()
        save(a)
    }

    private func sortAnnotations() {
        annotations.sort { ($0.locator.fraction, $0.createdAt) < ($1.locator.fraction, $1.createdAt) }
    }

    private func save(_ a: Annotation) {
        let notes = app.notes, entry = entry
        WriteQueue.shared.enqueue(WriteQueue.notes(entry.id), { try notes.upsert(a, in: entry) }, onError: writeFailed)
    }

    // MARK: Images and snips

    func saveImage(_ data: Data, fileExtension: String, caption: String, locator: Locator, chapter: String, announce: Bool = true) {
        let notes = app.notes, entry = entry
        let name = String((caption.isEmpty ? "figure" : caption).prefix(40))
        let chapter = chapter.isEmpty ? nil : chapter
        Task {
            do {
                // File and note are written in one queued step, in order with other edits.
                let a: Annotation = try await WriteQueue.shared.perform(WriteQueue.notes(entry.id)) {
                    let file = try notes.saveAsset(data, suggestedName: name, fileExtension: fileExtension, in: entry)
                    let a = Annotation(kind: .image, quote: caption, locator: locator, chapter: chapter, asset: file)
                    try notes.upsert(a, in: entry)
                    return a
                }
                annotations.append(a)
                sortAnnotations()
                if announce { app.show("Saved to your notes.") }
            } catch {
                app.show("Could not save the image: \(error.localizedDescription)", isError: true)
            }
        }
    }

    /// Captures a region of the reading area (in its own coordinates) into the notes.
    func snip(_ rect: CGRect, copyToClipboard: Bool) {
        isSnipping = false
        guard rect.width > 12, rect.height > 12 else { return }
        let finish: (NSImage?) -> Void = { [weak self] image in
            guard let self, let image, let png = image.pngRepresentation else { return }
            if copyToClipboard {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.writeObjects([image])
            }
            self.saveImage(png, fileExtension: "png", caption: "", locator: self.currentLocator, chapter: self.chapter)
        }
        if let web {
            let config = WKSnapshotConfigurationBox.make(rect: rect)
            web.webView.takeSnapshot(with: config) { image, _ in MainActor.assumeIsolated { finish(image) } }
        } else if let pdf {
            finish(pdf.image(of: rect))
        }
    }

    func assetURL(_ a: Annotation) -> URL? {
        a.asset.map { entry.assetsURL.appendingPathComponent($0) }
    }

    // MARK: Menus

    private func showImageMenu(_ image: WebReaderEvent.Image) {
        let locator = Locator(cfi: image.cfi, fraction: image.fraction, label: image.chapter.isEmpty ? nil : image.chapter)
        let menu = NSMenu()
        menu.addItem(ClosureMenuItem("Save Image to Notes") { [weak self] in
            self?.saveImage(image.data, fileExtension: image.fileExtension, caption: image.caption, locator: locator, chapter: image.chapter)
        })
        menu.addItem(ClosureMenuItem("Copy Image") {
            if let img = NSImage(data: image.data) {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.writeObjects([img])
            }
        })
        menu.addItem(ClosureMenuItem("Ask About This Image") { [weak self] in
            guard let self else { return }
            let file = FileManager.default.temporaryDirectory.appendingPathComponent("coreader-\(UUID().uuidString).\(image.fileExtension)")
            try? image.data.write(to: file)
            self.panel = .chat
            self.chat.attach(image: file)
        })
        popUp(menu, at: image.point ?? .zero)
    }

    private func showContextMenu(at point: CGPoint, hasSelection: Bool) {
        let menu = NSMenu()
        if hasSelection, selection != nil {
            menu.addItem(ClosureMenuItem("Highlight") { [weak self] in self?.highlight(self?.lastColor ?? .yellow) })
            menu.addItem(ClosureMenuItem("Add Note") { [weak self] in self?.noteOnSelection() })
            menu.addItem(ClosureMenuItem("Ask AI") { [weak self] in self?.askAboutSelection() })
            menu.addItem(ClosureMenuItem("Explain") { [weak self] in self?.glance(.explain) })
            menu.addItem(.separator())
            menu.addItem(ClosureMenuItem("Copy") { [weak self] in self?.copySelection() })
            menu.addItem(ClosureMenuItem("Look Up") { [weak self] in self?.glance(.define) })
        } else {
            menu.addItem(ClosureMenuItem("Add Note Here") { [weak self] in
                guard let self else { return }
                self.panel = .notes
                self.addNote("")
                if let last = self.annotations.last(where: { $0.kind == .note && $0.note.isEmpty }) { NotesFocus.shared.request(last.id) }
            })
            menu.addItem(ClosureMenuItem("Snip an Area…") { [weak self] in self?.isSnipping = true })
            menu.addItem(ClosureMenuItem("Ask About This Page") { [weak self] in
                self?.panel = .chat
                self?.chat.scope = .page
                self?.chat.focusComposer()
            })
        }
        popUp(menu, at: point)
    }

    private func popUp(_ menu: NSMenu, at point: CGPoint) {
        guard let view: NSView = web?.webView ?? pdf?.view else { return }
        // Points arrive with a top-left origin; AppKit views here are not flipped.
        let local = view.isFlipped ? point : CGPoint(x: point.x, y: view.bounds.height - point.y)
        menu.popUp(positioning: nil, at: local, in: view)
    }

    // MARK: AI

    func copySelection() {
        guard let s = selection else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(s.text, forType: .string)
        clearSelection()
    }

    func askAboutSelection() {
        guard let s = selection else { return }
        panel = .chat
        chat.quote(s)
        clearSelection()
    }

    func glance(_ kind: Glance.Kind) {
        guard let s = selection else { return }
        var g = Glance(kind: kind, selection: s)
        guard let agent = app.activeAgent else {
            g.isLoading = false
            g.failed = true
            g.answer = "No AI agent was found on this Mac. Install Claude Code, Codex or Antigravity, then reopen Coreader."
            glance = g
            return
        }
        glance = g
        let id = g.id
        let title = book.title, author = book.authorLine
        let prompt: String
        switch kind {
        case .explain:
            prompt = """
            I am reading "\(title)"\(author.isEmpty ? "" : " by \(author)"). Explain the selected passage plainly, in at most 90 words. \
            Say what it means and why it matters here. No preamble, no headings, no bullet lists.

            Surrounding paragraph:
            \(s.context)

            Selected passage:
            \(s.text)
            """
        case .define:
            prompt = """
            Define "\(s.text)" as it is used in this sentence from "\(title)". Give the meaning in one or two sentences, \
            then, if it is a term of art, one sentence on its usual sense. At most 60 words. No preamble.

            Sentence: \(s.context.prefix(600))
            """
        case .translate:
            prompt = """
            Translate the passage into clear, natural English (if it is already English, translate it into Hindi). \
            Output only the translation.

            \(s.text)
            """
        }
        glanceTask?.cancel()
        glanceTask = Task { [weak self] in
            do {
                let answer = try await AgentOneShot(agent: agent).complete(prompt, workingDirectory: nil, timeout: .seconds(90))
                guard let self, self.glance?.id == id else { return }
                self.glance?.answer = answer.trimmingCharacters(in: .whitespacesAndNewlines)
                self.glance?.isLoading = false
            } catch {
                guard let self, self.glance?.id == id else { return }
                self.glance?.answer = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                self.glance?.isLoading = false
                self.glance?.failed = true
            }
        }
    }

    /// Keeps a glance answer: highlights the passage with the answer as its note.
    func keepGlance() {
        guard let g = glance else { return }
        selection = g.selection
        highlight(lastColor, note: g.answer)
        glance = nil
        app.show("Saved to your notes.")
    }

    func recap() {
        showsWelcomeBack = false
        panel = .chat
        if let preset = chat.presets.first(where: { $0.title == "Recap so far" }) { chat.run(preset) }
    }

    func finish(rating: Int?) {
        app.setStatus(.read, for: entry.id)
        if let rating { app.setRating(rating, for: entry.id) }
        withAnimation { showsFinishCard = false }
    }
}

extension String {
    var collapsingWhitespace: String {
        replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

extension NSImage {
    var pngRepresentation: Data? {
        guard let tiff = tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }
}

/// `NSMenuItem` that runs a closure.
final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(_ title: String, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(run), keyEquivalent: "")
        target = self
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError("init(coder:) is not used") }

    @objc private func run() { handler() }
}

/// Lets a menu action put the cursor in a note that the notes panel is about to show.
@MainActor
@Observable
final class NotesFocus {
    static let shared = NotesFocus()
    var requested: String?
    func request(_ id: String) { requested = id }
}

extension ReaderModel {
    /// Development: select the first occurrence of `text` on the visible page.
    func debugSelect(_ text: String) {
        if let web {
            let js = """
            (() => { for (const {doc} of window.reader.view.renderer.getContents()) {
              const w = doc.createTreeWalker(doc.body, NodeFilter.SHOW_TEXT); let n
              while ((n = w.nextNode())) { const i = n.data.indexOf(\(String(data: try! JSONSerialization.data(withJSONObject: text, options: .fragmentsAllowed), encoding: .utf8)!))
                if (i >= 0) { const r = doc.createRange(); r.setStart(n, i); r.setEnd(n, Math.min(n.data.length, i + \(text.count)));
                  const s = doc.getSelection(); s.removeAllRanges(); s.addRange(r); return true } } } return false })()
            """
            web.webView.evaluateJavaScript(js) { _, _ in }
        } else if let pdf, let found = pdf.view.document?.findString(text, withOptions: .caseInsensitive).first {
            pdf.view.setCurrentSelection(found, animate: false)
        }
    }
}
