import AppKit
import CoreaderKit
import SwiftUI
import UniformTypeIdentifiers
import WebKit

/// What the web reader (foliate-js through `Web/bridge.js`) tells the app.
enum WebReaderEvent {
    struct Opened {
        var title: String
        var authors: [String]
        var language: String
        var publisher: String
        var summary: String
        var published: String
        var toc: [TOCItem]
        var cover: Data?
    }

    struct Relocated {
        var cfi: String
        var fraction: Double
        var chapter: String
        var page: String
        var visibleText: String
    }

    struct Selection {
        var text: String
        var cfi: String
        var context: String
        var chapter: String
        var fraction: Double
        /// Bounding box of the selection in the web view's coordinates (top-left origin).
        var rect: CGRect
    }

    struct Image {
        var data: Data
        var fileExtension: String
        var caption: String
        var cfi: String
        var fraction: Double
        var chapter: String
        var point: CGPoint?
    }

    struct SearchHit: Identifiable {
        let id = UUID()
        var cfi: String
        var pre: String
        var match: String
        var post: String
        var section: String
    }

    case ready
    case opened(Opened)
    case openFailed(String)
    case relocated(Relocated)
    case selection(Selection)
    case selectionCleared
    case annotationTapped(id: String, rect: CGRect)
    case imageContext(Image)
    case imageOpen(Image)
    case contextMenu(point: CGPoint, hasSelection: Bool)
    /// A click on the page that was not a link or a selection; `x` is 0...1 across the view.
    case tap(x: Double)
    case externalLink(URL)
    case textSection(index: Int, title: String, cfi: String, fraction: Double, text: String)
    case textDone
    case searchResults([SearchHit])
    case searchDone
    case escape
}

struct TOCItem: Identifiable, Hashable {
    let id = UUID()
    var label: String
    var href: String
    var depth: Int
}

/// Owns the `WKWebView` that renders every reflowable format. One instance per open book.
@MainActor
final class WebReaderController: NSObject {
    static let scheme = "coreader-app"

    let webView: WKWebView
    var onEvent: (WebReaderEvent) -> Void = { _ in }

    private let resources: ReaderResources
    private var isReady = false
    private var pendingOpen: (() -> Void)?

    override init() {
        resources = ReaderResources()
        let config = WKWebViewConfiguration()
        config.setURLSchemeHandler(resources, forURLScheme: Self.scheme)
        config.suppressesIncrementalRendering = true
        let proxy = MessageProxy()
        config.userContentController.add(proxy, name: "coreader")
        webView = ReaderWKWebView(frame: .zero, configuration: config)
        super.init()
        proxy.target = self
        webView.setValue(false, forKey: "drawsBackground")
        webView.allowsMagnification = false
        webView.navigationDelegate = self
        #if DEBUG
        webView.isInspectable = true
        #endif
        webView.load(URLRequest(url: URL(string: "\(Self.scheme)://web/reader.html")!))
    }

    // MARK: Commands

    struct AnnotationMark {
        var id: String
        var cfi: String
        var color: HighlightColor
        var hasNote: Bool

        var json: [String: Any] { ["id": id, "cfi": cfi, "color": color.rawValue, "hasNote": hasNote] }
    }

    func open(file: URL, lastCFI: String?, marks: [AnnotationMark], settings: [String: Any]) {
        resources.bookFile = file
        let options: [String: Any] = [
            "fileName": file.lastPathComponent,
            "lastCFI": lastCFI ?? "",
            "annotations": marks.map(\.json),
            "settings": settings,
        ]
        // The token keeps WebKit from serving a previous book from its cache.
        let url = "\(Self.scheme)://web/__book__/\(UUID().uuidString)/\(file.lastPathComponent.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? "book")"
        let run: () -> Void = { [weak self] in self?.call("open", url, options) }
        if isReady { run() } else { pendingOpen = run }
    }

    func next() { call("next") }
    func previous() { call("prev") }
    func go(toCFI cfi: String) { call("goTo", cfi) }
    func go(toHref href: String) { call("goTo", href) }
    func go(toFraction fraction: Double) { call("goToFraction", fraction) }
    func back() { call("back") }
    func apply(settings: [String: Any]) { call("applySettings", settings) }
    func add(_ mark: AnnotationMark) { call("addAnnotation", mark.json) }
    func update(_ mark: AnnotationMark) { call("updateAnnotation", mark.json) }
    func removeAnnotation(id: String) { call("removeAnnotation", id) }
    func showAnnotation(id: String) { call("showAnnotation", id) }
    func clearSelection() { call("clearSelection") }
    func search(_ query: String) { call("search", query) }
    func clearSearch() { call("clearSearch") }
    func extractText() { call("extractText") }

    private func call(_ method: String, _ arguments: Any...) {
        guard let data = try? JSONSerialization.data(withJSONObject: arguments, options: [.fragmentsAllowed]),
              let json = String(data: data, encoding: .utf8) else { return }
        // Arguments travel as a JSON array literal, so no string is ever spliced into script.
        webView.evaluateJavaScript("window.reader.\(method)(...\(json))") { _, error in
            if let error { NSLog("reader.%@ failed: %@", method, error.localizedDescription) }
        }
    }

    // MARK: Events

    fileprivate func handle(_ body: Any) {
        guard let m = body as? [String: Any], let type = m["type"] as? String else { return }
        func s(_ k: String) -> String { m[k] as? String ?? "" }
        func d(_ k: String) -> Double { (m[k] as? NSNumber)?.doubleValue ?? 0 }
        func rect(_ k: String) -> CGRect {
            guard let r = m[k] as? [String: Any] else { return .zero }
            func n(_ k: String) -> Double { (r[k] as? NSNumber)?.doubleValue ?? 0 }
            return CGRect(x: n("x"), y: n("y"), width: n("width"), height: n("height"))
        }
        func point(_ k: String) -> CGPoint? {
            guard let r = m[k] as? [String: Any] else { return nil }
            return CGPoint(x: (r["x"] as? NSNumber)?.doubleValue ?? 0, y: (r["y"] as? NSNumber)?.doubleValue ?? 0)
        }
        func image() -> WebReaderEvent.Image? {
            guard let (data, ext) = Self.decode(dataURL: s("dataURL")) else { return nil }
            return .init(data: data, fileExtension: ext, caption: s("caption"), cfi: s("cfi"),
                         fraction: d("fraction"), chapter: s("chapter"), point: point("point"))
        }

        switch type {
        case "ready":
            isReady = true
            onEvent(.ready)
            pendingOpen?()
            pendingOpen = nil
        case "opened":
            let toc = (m["toc"] as? [[String: Any]] ?? []).map {
                TOCItem(label: $0["label"] as? String ?? "", href: $0["href"] as? String ?? "", depth: $0["depth"] as? Int ?? 0)
            }
            onEvent(.opened(.init(
                title: s("title"), authors: m["authors"] as? [String] ?? [], language: s("language"),
                publisher: s("publisher"), summary: s("description"), published: s("published"),
                toc: toc, cover: Self.decode(dataURL: s("cover"))?.0)))
        case "openFailed":
            onEvent(.openFailed(s("message")))
        case "relocate":
            onEvent(.relocated(.init(cfi: s("cfi"), fraction: d("fraction"), chapter: s("chapter"),
                                     page: s("page"), visibleText: s("visibleText"))))
        case "selection":
            onEvent(.selection(.init(text: s("text"), cfi: s("cfi"), context: s("context"),
                                     chapter: s("chapter"), fraction: d("fraction"), rect: rect("rect"))))
        case "selectionCleared":
            onEvent(.selectionCleared)
        case "annotationTap":
            onEvent(.annotationTapped(id: s("id"), rect: rect("rect")))
        case "imageContext":
            if let image = image() { onEvent(.imageContext(image)) }
        case "imageOpen":
            if let image = image() { onEvent(.imageOpen(image)) }
        case "contextMenu":
            onEvent(.contextMenu(point: point("point") ?? .zero, hasSelection: m["hasSelection"] as? Bool ?? false))
        case "tap":
            onEvent(.tap(x: d("x")))
        case "externalLink":
            if let url = URL(string: s("href")) { onEvent(.externalLink(url)) }
        case "textSection":
            onEvent(.textSection(index: m["index"] as? Int ?? 0, title: s("title"), cfi: s("cfi"),
                                 fraction: d("fraction"), text: s("text")))
        case "textDone":
            onEvent(.textDone)
        case "searchResults":
            let label = s("label")
            let hits = (m["items"] as? [[String: Any]] ?? []).map {
                WebReaderEvent.SearchHit(cfi: $0["cfi"] as? String ?? "", pre: $0["pre"] as? String ?? "",
                                         match: $0["match"] as? String ?? "", post: $0["post"] as? String ?? "", section: label)
            }
            onEvent(.searchResults(hits))
        case "searchDone":
            onEvent(.searchDone)
        case "escape":
            onEvent(.escape)
        case "log":
            DebugHooks.log("[reader] \(s("level")): \(s("message"))")
        default:
            break
        }
    }

    private static func decode(dataURL: String) -> (Data, String)? {
        guard dataURL.hasPrefix("data:"), let comma = dataURL.firstIndex(of: ",") else { return nil }
        let header = dataURL[dataURL.index(dataURL.startIndex, offsetBy: 5)..<comma]
        let mime = header.split(separator: ";").first.map(String.init) ?? ""
        guard let data = Data(base64Encoded: String(dataURL[dataURL.index(after: comma)...])) else { return nil }
        let ext = UTType(mimeType: mime)?.preferredFilenameExtension ?? "png"
        return (data, ext == "jpeg" ? "jpg" : ext)
    }
}

extension WebReaderController: WKNavigationDelegate {
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        guard let url = navigationAction.request.url else { return .cancel }
        // The reader page and the blob/about documents foliate creates stay inside; anything
        // else is a link out of the book.
        if url.scheme == Self.scheme || url.scheme == "blob" || url.scheme == "about" { return .allow }
        if navigationAction.navigationType == .linkActivated, ["http", "https", "mailto"].contains(url.scheme ?? "") {
            onEvent(.externalLink(url))
        }
        return .cancel
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        isReady = false
        onEvent(.openFailed("The reader stopped unexpectedly. Reopen the book to continue."))
    }
}

/// `WKUserContentController` retains its handler; the proxy breaks that cycle.
private final class MessageProxy: NSObject, WKScriptMessageHandler {
    weak var target: WebReaderController?

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.handle(message.body)
    }
}

/// The web content draws its own context menu through the bridge.
private final class ReaderWKWebView: WKWebView {
    override func willOpenMenu(_ menu: NSMenu, with event: NSEvent) {
        menu.removeAllItems()
    }
}

/// Serves the bundled web reader and the open book over one origin, with a CSP that
/// lets only our own scripts run: books can carry JavaScript and must never execute it.
private final class ReaderResources: NSObject, WKURLSchemeHandler, @unchecked Sendable {
    /// Read on WebKit's callback and written from the main actor before a load starts.
    private let lock = NSLock()
    private var _bookFile: URL?
    var bookFile: URL? {
        get { lock.withLock { _bookFile } }
        set { lock.withLock { _bookFile = newValue } }
    }

    private let webRoot: URL = Bundle.main.resourceURL!.appendingPathComponent("Web", isDirectory: true)

    private static let csp = [
        "default-src 'self' blob: data:",
        "script-src 'self'",
        "style-src 'self' blob: data: 'unsafe-inline'",
        "img-src 'self' blob: data:",
        "font-src 'self' blob: data:",
        "media-src 'self' blob: data:",
        "connect-src 'self' blob: data:",
        "frame-src 'self' blob: data:",
        "object-src 'none'",
        "form-action 'none'",
    ].joined(separator: "; ")

    func webView(_ webView: WKWebView, start task: any WKURLSchemeTask) {
        guard let url = task.request.url else { return fail(task, 400) }
        let fileURL: URL?
        if url.path.hasPrefix("/__book__/") {
            fileURL = bookFile
        } else {
            let candidate = webRoot.appendingPathComponent(url.path).standardizedFileURL
            // Never serve anything outside the bundled folder.
            fileURL = candidate.path.hasPrefix(webRoot.standardizedFileURL.path) ? candidate : nil
        }
        guard let fileURL, let data = try? Data(contentsOf: fileURL, options: .mappedIfSafe) else { return fail(task, 404) }

        let mime: String
        switch fileURL.pathExtension.lowercased() {
        case "js", "mjs": mime = "text/javascript"
        case "html": mime = "text/html"
        case "css": mime = "text/css"
        case "json": mime = "application/json"
        default: mime = UTType(filenameExtension: fileURL.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
        }
        var headers = [
            "Content-Type": mime == "text/html" || mime == "text/javascript" ? "\(mime); charset=utf-8" : mime,
            "Content-Length": String(data.count),
            "Cache-Control": "no-store",
            "Access-Control-Allow-Origin": "*",
        ]
        if mime == "text/html" { headers["Content-Security-Policy"] = Self.csp }
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: headers)!
        task.didReceive(response)
        task.didReceive(data)
        task.didFinish()
    }

    func webView(_ webView: WKWebView, stop task: any WKURLSchemeTask) {}

    private func fail(_ task: any WKURLSchemeTask, _ status: Int) {
        task.didFailWithError(URLError(status == 404 ? .fileDoesNotExist : .badURL))
    }
}

/// Hosts the controller's web view in SwiftUI.
struct WebReaderView: NSViewRepresentable {
    let controller: WebReaderController

    func makeNSView(context: Context) -> WKWebView { controller.webView }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
}
