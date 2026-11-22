import AppKit
import CoreaderKit
import PDFKit
import SwiftUI
import WebKit

enum PDFReaderEvent {
    case opened(toc: [TOCItem], pageCount: Int)
    case openFailed(String)
    case relocated(page: Int, count: Int, chapter: String, visibleText: String)
    case selection(ReaderSelection)
    case selectionCleared
    case annotationTapped(id: String, rect: CGRect)
    /// Point in the view with a top-left origin.
    case contextMenu(point: CGPoint, hasSelection: Bool)
    case tap
    case link(URL)
    /// A citation in the text was clicked: the bibliography entry it points to.
    case citation(entry: String, rect: CGRect)
}

/// PDF reading on PDFKit. Highlights are drawn as annotations in memory only: the PDF
/// file is never modified, the notes file is the record.
@MainActor
final class PDFReaderController: NSObject {
    let view = ReaderPDFView()
    var onEvent: (PDFReaderEvent) -> Void = { _ in }

    private var document: PDFDocument?
    private var marks: [String: [PDFAnnotation]] = [:]
    private var outline: [(page: Int, label: String)] = []
    private var selectionTask: Task<Void, Never>?
    private var settings = ReaderSettings()
    private var searchMarks: [PDFAnnotation] = []

    override init() {
        super.init()
        view.controller = self
        view.autoScales = true
        view.displaysPageBreaks = true
        view.pageShadowsEnabled = false
        view.wantsLayer = true
        view.layerUsesCoreImageFilters = true
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(pageChanged), name: .PDFViewPageChanged, object: view)
        center.addObserver(self, selector: #selector(selectionChanged), name: .PDFViewSelectionChanged, object: view)
        // PDFView hands mouse events to private subviews, so overriding them on a subclass
        // sees nothing. A local monitor sees every click before the view does.
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseUp, .rightMouseDown]) { [weak self] event in
            // Monitors run on the main thread; the event never leaves it.
            nonisolated(unsafe) let event = event
            let swallow = MainActor.assumeIsolated { self?.intercept(event) == false }
            return swallow ? nil : event
        }
    }

    private var monitor: Any?
    private var downPoint: CGPoint?

    /// Must be called when the book closes: the monitor would otherwise outlive the view.
    func dispose() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        NotificationCenter.default.removeObserver(self)
    }

    /// Returns false when the event was handled here and must not reach the view.
    private func intercept(_ event: NSEvent) -> Bool {
        guard let window = view.window, event.window === window,
              let hit = window.contentView?.hitTest(event.locationInWindow), hit === view || hit.isDescendant(of: view) else { return true }
        let point = view.convert(event.locationInWindow, from: nil)
        switch event.type {
        case .leftMouseDown:
            downPoint = point
            if event.clickCount == 1, !event.modifierFlags.contains(.command), citation(at: point) {
                downPoint = nil
                return false
            }
        case .leftMouseUp:
            // A click, not a drag-selection.
            if let down = downPoint, hypot(point.x - down.x, point.y - down.y) < 3, (view.currentSelection?.string ?? "").isEmpty {
                clicked(at: point)
            }
            downPoint = nil
        case .rightMouseDown:
            contextMenu(at: point)
            return false
        default:
            break
        }
        return true
    }

    // MARK: Opening

    func open(file: URL, page: Int, annotations: [Annotation], settings: ReaderSettings, theme: ReaderTheme) {
        guard let document = PDFDocument(url: file) else {
            return onEvent(.openFailed("This PDF could not be opened. It may be damaged or password-protected."))
        }
        self.document = document
        view.document = document
        apply(settings: settings, theme: theme)
        for a in annotations { add(a) }

        var items: [TOCItem] = []
        func walk(_ node: PDFOutline, depth: Int) {
            for i in 0..<node.numberOfChildren {
                guard let child = node.child(at: i) else { continue }
                if let label = child.label, let dest = child.destination?.page {
                    let index = document.index(for: dest)
                    items.append(TOCItem(label: label, href: String(index), depth: depth))
                    outline.append((index, label))
                }
                walk(child, depth: depth + 1)
            }
        }
        if let root = document.outlineRoot { walk(root, depth: 0) }
        outline.sort { $0.page < $1.page }

        onEvent(.opened(toc: items, pageCount: document.pageCount))
        // Layout has to settle before a jump lands on the right page.
        DispatchQueue.main.async { [weak self] in
            self?.go(toPage: page, animated: false)
            self?.pageChanged()
        }
    }

    func apply(settings: ReaderSettings, theme: ReaderTheme) {
        self.settings = settings
        applyLayout()
        view.displaysAsBook = false
        view.displayDirection = .vertical
        view.autoScales = true
        let p = theme.palette
        view.backgroundColor = NSColor(p.page)

        // One colour matrix maps the PDF's white paper to the theme's page colour and its
        // black ink to the theme's ink, so a PDF sits in the same surface as a book.
        let page = NSColor(p.page).usingColorSpace(.sRGB) ?? .white
        let ink = NSColor(p.ink).usingColorSpace(.sRGB) ?? .black
        var filters: [CIFilter] = []
        var from = (r: CGFloat(0), g: CGFloat(0), b: CGFloat(0)), to = (r: page.redComponent, g: page.greenComponent, b: page.blueComponent)
        from = (ink.redComponent, ink.greenComponent, ink.blueComponent)
        if theme.isDark {
            // Invert first (keeping hues), then scale into the dark page/ink range.
            if let invert = CIFilter(name: "CIColorInvert") { filters.append(invert) }
            if let hue = CIFilter(name: "CIHueAdjust", parameters: [kCIInputAngleKey: Double.pi]) { filters.append(hue) }
            swap(&from, &to)
        }
        if let matrix = CIFilter(name: "CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: to.r - from.r, y: 0, z: 0, w: 0),
            "inputGVector": CIVector(x: 0, y: to.g - from.g, z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: to.b - from.b, w: 0),
            "inputBiasVector": CIVector(x: from.r, y: from.g, z: from.b, w: 0),
        ]) { filters.append(matrix) }
        view.contentFilters = filters
    }

    /// Two pages only when each would still be comfortably readable.
    private var availableWidth: CGFloat = 1200

    func setAvailableWidth(_ width: CGFloat) {
        guard abs(width - availableWidth) > 1 else { return }
        availableWidth = width
        applyLayout()
    }

    private func applyLayout() {
        let scrolls = settings.pageTurn == .scroll
        let mode: PDFDisplayMode = scrolls ? .singlePageContinuous : (settings.twoPages && availableWidth >= 1040 ? .twoUp : .singlePage)
        guard view.displayMode != mode else { return }
        let page = view.currentPage
        view.displayMode = mode
        view.autoScales = true
        if let page { view.go(to: page) }
    }

    // MARK: Navigation

    var pageIndex: Int {
        guard let document, let page = view.currentPage else { return 0 }
        return document.index(for: page)
    }

    private var step: Int { view.displayMode == .twoUp ? 2 : 1 }

    func next() { go(toPage: pageIndex + step, animated: true, forward: true) }
    func previous() { go(toPage: pageIndex - step, animated: true, forward: false) }

    func go(toPage index: Int, animated: Bool = false, forward: Bool = true) {
        guard let document, document.pageCount > 0 else { return }
        let clamped = min(max(index, 0), document.pageCount - 1)
        guard let page = document.page(at: clamped) else { return }
        if animated, settings.pageTurn != .none, settings.pageTurn != .scroll,
           !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            let transition = CATransition()
            transition.type = .push
            transition.subtype = forward ? .fromRight : .fromLeft
            transition.duration = 0.26
            transition.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            view.layer?.add(transition, forKey: "page")
        }
        view.go(to: page)
    }

    func go(toFraction f: Double) {
        guard let document else { return }
        go(toPage: Int((Double(document.pageCount - 1) * min(max(f, 0), 1)).rounded()))
    }

    @objc private func pageChanged() {
        guard let document, let page = view.currentPage else { return }
        let index = document.index(for: page)
        let chapter = outline.last { $0.page <= index }?.label ?? ""
        var text = page.string ?? ""
        if view.displayMode == .twoUp, let nextPage = document.page(at: index + 1) { text += "\n" + (nextPage.string ?? "") }
        onEvent(.relocated(page: index, count: document.pageCount, chapter: chapter, visibleText: String(text.prefix(6000))))
    }

    // MARK: Selection

    @objc private func selectionChanged() {
        selectionTask?.cancel()
        selectionTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(160))
            guard !Task.isCancelled else { return }
            self?.reportSelection()
        }
    }

    private func reportSelection() {
        guard let document, let selection = view.currentSelection, let page = selection.pages.first,
              let text = selection.string?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            return onEvent(.selectionCleared)
        }
        let index = document.index(for: page)
        let rects = selection.selectionsByLine().filter { $0.pages.first == page }.map { $0.bounds(for: page) }
            .filter { $0.width > 0.5 && $0.height > 0.5 }
        let bounds = view.convert(selection.bounds(for: page), from: page)
        let top = CGRect(x: bounds.minX, y: view.bounds.height - bounds.maxY, width: bounds.width, height: bounds.height)
        let chapter = outline.last { $0.page <= index }?.label ?? ""
        let locator = Locator(page: index, rects: rects.map { [$0.minX, $0.minY, $0.width, $0.height].map { Double($0) } },
                              fraction: document.pageCount > 1 ? Double(index) / Double(document.pageCount - 1) : 0, label: "p. \(index + 1)")
        onEvent(.selection(ReaderSelection(text: text, context: Self.context(around: text, in: page.string ?? ""),
                                           locator: locator, chapter: chapter, rect: top)))
    }

    /// Roughly the paragraph around the selected text on its page.
    private static func context(around text: String, in page: String) -> String {
        let probe = String(text.prefix(40))
        guard let range = page.range(of: probe) else { return text }
        let start = page.index(range.lowerBound, offsetBy: -700, limitedBy: page.startIndex) ?? page.startIndex
        let end = page.index(range.lowerBound, offsetBy: text.count + 700, limitedBy: page.endIndex) ?? page.endIndex
        return String(page[start..<end]).collapsingWhitespace
    }

    func clearSelection() { view.clearSelection() }

    // MARK: Highlights

    func add(_ a: Annotation) {
        guard a.kind == .highlight, let index = a.locator.page, let page = document?.page(at: index),
              let rects = a.locator.rects, !rects.isEmpty else { return }
        remove(id: a.id)
        var made: [PDFAnnotation] = []
        for r in rects where r.count == 4 {
            let rect = CGRect(x: r[0], y: r[1], width: r[2], height: r[3])
            let mark = PDFAnnotation(bounds: rect, forType: .highlight, withProperties: nil)
            mark.color = NSColor(a.color.color).withAlphaComponent(0.42)
            mark.userName = a.id
            page.addAnnotation(mark)
            made.append(mark)
        }
        if !a.note.isEmpty, let last = rects.last, last.count == 4 {
            // A thin rule under the last line marks a highlight that carries a note.
            let line = PDFAnnotation(bounds: CGRect(x: last[0], y: last[1] - 1.5, width: last[2], height: 1.2), forType: .square, withProperties: nil)
            line.color = .clear
            line.interiorColor = NSColor(a.color.color)
            line.border = { let b = PDFBorder(); b.lineWidth = 0; return b }()
            line.userName = a.id
            page.addAnnotation(line)
            made.append(line)
        }
        marks[a.id] = made
    }

    func update(_ a: Annotation) { add(a) }

    func remove(id: String) {
        for mark in marks[id] ?? [] { mark.page?.removeAnnotation(mark) }
        marks[id] = nil
    }

    // MARK: Search

    private var searchContinuation: CheckedContinuation<Void, Never>?
    private var searchFound: [PDFSelection] = []
    private static let searchLimit = 300

    /// Searches with PDFKit's incremental search, which reports matches as it goes and
    /// can be stopped, so a common word in a long document neither freezes the window nor
    /// collects thousands of matches.
    func search(_ query: String) async -> [SearchHit] {
        clearSearch()
        guard let document else { return [] }
        document.cancelFindString()
        finishSearch()
        // Matches stay on the main actor in `searchFound`; the continuation only signals the end.
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            searchFound = []
            searchContinuation = c
            document.delegate = self
            document.beginFindString(query, withOptions: [.caseInsensitive, .diacriticInsensitive])
        }
        let found = searchFound
        searchFound = []
        var hits: [SearchHit] = []
        for selection in found {
            guard let page = selection.pages.first, let match = selection.string else { continue }
            let index = document.index(for: page)
            let extended = selection.copy() as! PDFSelection
            extended.extendForLineBoundaries()
            let line = (extended.string ?? match).collapsingWhitespace
            let parts = line.range(of: match, options: [.caseInsensitive, .diacriticInsensitive])
            let bounds = selection.bounds(for: page)
            hits.append(SearchHit(
                locator: Locator(page: index, rects: [[bounds.minX, bounds.minY, bounds.width, bounds.height].map { Double($0) }],
                                 fraction: Double(index) / Double(max(document.pageCount - 1, 1)), label: "p. \(index + 1)"),
                before: parts.map { String(line[..<$0.lowerBound]) } ?? "", match: match,
                after: parts.map { String(line[$0.upperBound...]) } ?? "", section: "Page \(index + 1)"))
            let mark = PDFAnnotation(bounds: bounds, forType: .highlight, withProperties: nil)
            mark.color = NSColor.systemOrange.withAlphaComponent(0.35)
            page.addAnnotation(mark)
            searchMarks.append(mark)
        }
        return hits
    }

    private func finishSearch() {
        searchContinuation?.resume()
        searchContinuation = nil
    }

    func clearSearch() {
        document?.cancelFindString()
        for mark in searchMarks { mark.page?.removeAnnotation(mark) }
        searchMarks = []
    }

    // MARK: Snip

    /// Renders the part of the page under `rect` (view coordinates, top-left origin) at
    /// print quality, straight from the PDF and so free of the theme tint.
    func image(of rect: CGRect) -> NSImage? {
        let viewRect = CGRect(x: rect.minX, y: view.bounds.height - rect.maxY, width: rect.width, height: rect.height)
        guard let page = view.page(for: CGPoint(x: viewRect.midX, y: viewRect.midY), nearest: true) else { return nil }
        let pageRect = view.convert(viewRect, to: page).intersection(page.bounds(for: .cropBox))
        guard pageRect.width > 2, pageRect.height > 2 else { return nil }
        let scale: CGFloat = 3
        let size = NSSize(width: pageRect.width * scale, height: pageRect.height * scale)
        let image = NSImage(size: size, flipped: false) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            ctx.setFillColor(NSColor.white.cgColor)
            ctx.fill(CGRect(origin: .zero, size: size))
            ctx.scaleBy(x: scale, y: scale)
            ctx.translateBy(x: -pageRect.minX, y: -pageRect.minY)
            page.draw(with: .cropBox, to: ctx)
            return true
        }
        return image
    }

    // MARK: From the view

    private func clicked(at point: CGPoint) {
        guard let page = view.page(for: point, nearest: false) else { return onEvent(.tap) }
        let pagePoint = view.convert(point, to: page)
        if let hit = page.annotation(at: pagePoint), let id = hit.userName, marks[id] != nil {
            let b = view.convert(hit.bounds, from: page)
            onEvent(.annotationTapped(id: id, rect: CGRect(x: b.minX, y: view.bounds.height - b.maxY, width: b.width, height: b.height)))
        } else {
            onEvent(.tap)
        }
    }

    /// If the click landed on an in-document link that leads to a bibliography entry,
    /// reports that entry instead of jumping away from the page being read.
    private func citation(at point: CGPoint) -> Bool {
        guard let page = view.page(for: point, nearest: false) else { return false }
        let pagePoint = view.convert(point, to: page)
        guard let link = page.annotations.first(where: { $0.type == "Link" && $0.bounds.insetBy(dx: -1, dy: -1).contains(pagePoint) }),
              let destination = link.destination ?? (link.action as? PDFActionGoTo)?.destination,
              let target = destination.page else { return false }
        // The text just below the link's landing point is the entry.
        let width = target.bounds(for: .cropBox).width
        let top = destination.point.y > 100_000 ? target.bounds(for: .cropBox).maxY : destination.point.y
        let area = CGRect(x: 0, y: top - 150, width: width, height: 153)
        guard let raw = target.selection(for: area)?.string else { return false }
        let text = raw.replacingOccurrences(of: "-\n", with: "").collapsingWhitespace
        // Only bibliography entries: the first "[12] ..." or "12. ..." at the landing
        // point, up to the next entry. Links to sections, figures and equations keep
        // their normal behaviour. The selection can include the tail of the entry above.
        var entry: String
        if let match = text.firstMatch(of: /\[(\d{1,3})\]\s+/) {
            entry = String(text[match.range.upperBound...])
            if let next = entry.firstMatch(of: /\s\[\d{1,3}\]\s/) { entry = String(entry[..<next.range.lowerBound]) }
        } else if let match = text.firstMatch(of: /(?:^|\s)(\d{1,3})\.\s+(?=\p{Lu})/), let number = Int(match.1) {
            entry = String(text[match.range.upperBound...])
            if let next = entry.range(of: " \(number + 1). ") { entry = String(entry[..<next.lowerBound]) }
        } else {
            return false
        }
        guard entry.count > 20 else { return false }
        let b = view.convert(link.bounds, from: page)
        onEvent(.citation(entry: entry.trimmingCharacters(in: .whitespaces),
                          rect: CGRect(x: b.minX, y: view.bounds.height - b.maxY, width: b.width, height: b.height)))
        return true
    }

    private func contextMenu(at point: CGPoint) {
        let hasSelection = !(view.currentSelection?.string ?? "").isEmpty
        if hasSelection { reportSelection() }
        onEvent(.contextMenu(point: CGPoint(x: point.x, y: view.bounds.height - point.y), hasSelection: hasSelection))
    }
}

final class ReaderPDFView: PDFView {
    weak var controller: PDFReaderController?

    override func keyDown(with event: NSEvent) {
        guard displayMode == .singlePage || displayMode == .twoUp,
              !event.modifierFlags.contains(.command) else { return super.keyDown(with: event) }
        switch event.keyCode {
        case 124, 121: controller?.next()                                   // right arrow, page down
        case 123, 116: controller?.previous()                               // left arrow, page up
        case 49: event.modifierFlags.contains(.shift) ? controller?.previous() : controller?.next()   // space
        default: super.keyDown(with: event)
        }
    }
}

struct PDFReaderView: NSViewRepresentable {
    let controller: PDFReaderController

    func makeNSView(context: Context) -> PDFView { controller.view }
    func updateNSView(_ nsView: PDFView, context: Context) {}
}

/// Small helper so callers outside WebKit-importing files can ask for a region snapshot.
enum WKSnapshotConfigurationBox {
    @MainActor
    static func make(rect: CGRect) -> WKSnapshotConfiguration {
        let config = WKSnapshotConfiguration()
        config.rect = rect
        return config
    }
}

extension PDFReaderController: PDFDocumentDelegate {
    nonisolated func didMatchString(_ instance: PDFSelection) {
        nonisolated(unsafe) let instance = instance
        MainActor.assumeIsolated {
            guard searchContinuation != nil else { return }
            searchFound.append(instance)
            if searchFound.count >= Self.searchLimit { document?.cancelFindString(); finishSearch() }
        }
    }

    nonisolated func documentDidEndDocumentFind(_ notification: Notification) {
        MainActor.assumeIsolated { finishSearch() }
    }
}
