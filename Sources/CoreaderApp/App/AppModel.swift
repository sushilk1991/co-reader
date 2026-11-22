import AppKit
import CoreaderKit
import SwiftUI

/// Runs blocking library work off the main actor.
func offMain<T: Sendable>(_ work: @escaping @Sendable () throws -> T) async throws -> T {
    try await Task.detached(priority: .userInitiated) { try work() }.value
}

enum Route: Equatable {
    case shelf
    case reader(bookID: String)
}

enum ShelfOverlay: String, Identifiable {
    case review, graph, settings, addLink
    var id: String { rawValue }
}

/// App-wide state: the library, the route, settings, detected agents.
@MainActor
@Observable
final class AppModel {
    private(set) var library: LibraryStore
    let notes = NotesStore()
    let textStore = BookTextStore()

    var books: [BookEntry] = []
    var route: Route = .shelf
    var overlay: ShelfOverlay?
    var reader: ReaderModel?
    var notice: Notice?
    var confirmDelete: BookEntry?
    var skillJob: SkillJob?
    var isLoaded = false

    var settings = ReaderSettings.load() { didSet { settings.save() } }
    var systemIsDark = false

    var agents: [DetectedAgent] = []
    var agentsChecked = false
    var preferredAgent: AgentKind? {
        didSet { UserDefaults.standard.set(preferredAgent?.rawValue, forKey: "agent.preferred") }
    }

    var hasOnboarded: Bool = UserDefaults.standard.bool(forKey: "onboarding.done") {
        didSet { UserDefaults.standard.set(hasOnboarded, forKey: "onboarding.done") }
    }
    var generatesCovers: Bool = UserDefaults.standard.object(forKey: "covers.generate") as? Bool ?? true {
        didSet { UserDefaults.standard.set(generatesCovers, forKey: "covers.generate") }
    }

    /// Book ids with an import step still running (metadata lookup, cover generation).
    var busyBooks: [String: String] = [:]
    /// Bumped when a cover file changes so views reload the image.
    var coverVersion: [String: Int] = [:]

    let review: ReviewModel
    private(set) var importer: ImportService!
    private var pendingLinks: [URL] = []

    struct Notice: Identifiable, Equatable {
        let id = UUID()
        var text: String
        var isError = false
    }

    init() {
        let config = LibraryConfig.load()
        library = LibraryStore(root: config.libraryRoot)
        review = ReviewModel(libraryRoot: config.libraryRoot)
        preferredAgent = UserDefaults.standard.string(forKey: "agent.preferred").flatMap(AgentKind.init(rawValue:))
        importer = ImportService(app: self)
    }

    // MARK: Theme

    var theme: ReaderTheme {
        guard settings.followsSystemAppearance else { return settings.theme }
        if systemIsDark { return settings.theme.isDark ? settings.theme : .dusk }
        return settings.theme.isDark ? .paper : settings.theme
    }

    var palette: Palette { theme.palette }

    // MARK: Lifecycle

    func start() async {
        let library = library
        do {
            books = try await offMain {
                try library.prepare()
                return try library.allBooks()
            }
        } catch {
            show("Could not open the library: \(error.localizedDescription)", isError: true)
        }
        isLoaded = true
        review.reload(app: self)
        let links = pendingLinks
        pendingLinks = []
        for url in links { handle(url: url) }
        Task {
            agents = await AgentDetector().detect()
            agentsChecked = true
            if preferredAgent == nil || !agents.contains(where: { $0.kind == preferredAgent }) {
                preferredAgent = agents.first?.kind
            }
        }
    }

    var activeAgent: DetectedAgent? {
        agents.first { $0.kind == preferredAgent } ?? agents.first
    }

    func reloadBooks() async {
        let library = library
        if let all = try? await offMain({ try library.allBooks() }) { books = all }
    }

    /// Moves the library to another folder (onboarding and Settings). Existing books are
    /// not moved; the new folder is opened as it is.
    func useLibrary(at root: URL) async {
        var config = LibraryConfig.load()
        config.libraryRoot = root
        try? config.save()
        library = LibraryStore(root: root)
        review.libraryRoot = root
        await start()
    }

    func entry(_ id: String) -> BookEntry? { books.first { $0.id == id } }

    func show(_ text: String, isError: Bool = false) {
        let notice = Notice(text: text, isError: isError)
        self.notice = notice
        Task {
            try? await Task.sleep(for: .seconds(isError ? 7 : 3.5))
            if self.notice == notice { self.notice = nil }
        }
    }

    // MARK: Books

    /// Applies a change to a book and writes `book.json`.
    func update(_ id: String, _ change: (inout Book) -> Void) {
        guard let index = books.firstIndex(where: { $0.id == id }) else { return }
        change(&books[index].book)
        let entry = books[index]
        let library = library
        Task {
            do { try await offMain { try library.save(entry.book, in: entry.folder) } }
            catch { show("Could not save changes to “\(entry.book.title)”.", isError: true) }
        }
    }

    func replace(_ entry: BookEntry) {
        if let index = books.firstIndex(where: { $0.id == entry.id }) { books[index] = entry } else { books.append(entry) }
        coverVersion[entry.id, default: 0] += 1
    }

    func setStatus(_ status: ReadingStatus, for id: String) {
        update(id) { book in
            book.status = status
            if status == .read {
                book.finishedAt = book.finishedAt ?? Date()
            } else {
                book.finishedAt = nil
            }
        }
    }

    func setRating(_ rating: Int?, for id: String) {
        update(id) { $0.rating = rating }
    }

    func delete(_ id: String) {
        guard let entry = entry(id) else { return }
        if case .reader(let open) = route, open == id { closeReader() }
        books.removeAll { $0.id == id }
        let library = library
        Task {
            do { try await offMain { try library.delete(id: id) } }
            catch { show("Could not remove “\(entry.book.title)”.", isError: true) }
            show("Moved “\(entry.book.title)” to the Trash.")
        }
    }

    func makeSkill(from id: String) {
        guard let entry = entry(id) else { return }
        skillJob = SkillJob(entry: entry)
    }

    func revealInFinder(_ id: String) {
        guard let entry = entry(id) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([entry.notesURLIfPresent ?? entry.fileURL])
    }

    // MARK: Reader

    func open(_ id: String, at link: DeepLink? = nil) {
        guard let entry = entry(id) else { return }
        if reader?.entry.id != id {
            reader?.close()
            reader = ReaderModel(entry: entry, app: self)
        }
        withAnimation(.easeInOut(duration: 0.28)) { route = .reader(bookID: id) }
        if let link { reader?.follow(link) }
    }

    func closeReader() {
        reader?.close()
        withAnimation(.easeInOut(duration: 0.28)) { route = .shelf }
        reader = nil
        review.reload(app: self)
    }

    // MARK: Links

    /// `coreader://open?...` jumps into a book; `coreader://save?url=...` saves an article
    /// (the browser extension); file URLs are imported.
    func handle(url: URL) {
        guard isLoaded else { pendingLinks.append(url); return }
        if url.isFileURL {
            importer.importFiles([url], openFirst: true)
            return
        }
        guard url.scheme == DeepLink.scheme else { return }
        if url.host == "save" {
            let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            if let target = items.first(where: { $0.name == "url" })?.value.flatMap(URL.init(string:)) {
                importer.importLink(target.absoluteString, selection: items.first { $0.name == "selection" }?.value)
            }
            return
        }
        guard let link = DeepLink(url: url) else { return }
        let bookID: String
        switch link {
        case .book(let id): bookID = id
        case .annotation(let id, _): bookID = id
        case .location(let id, _): bookID = id
        }
        guard entry(bookID) != nil else { return show("That book is not in this library.", isError: true) }
        open(bookID, at: link)
    }
}

extension BookEntry {
    var notesURLIfPresent: URL? {
        FileManager.default.fileExists(atPath: notesURL.path) ? notesURL : nil
    }
}

// MARK: - Unattended driving (development)

extension AppModel {
    /// One-line commands from `DebugHooks`; see `scripts/dev_run.sh`.
    func debug(_ line: String) {
        let parts = line.split(separator: " ", maxSplits: 1).map(String.init)
        let arg = parts.count > 1 ? parts[1] : ""
        switch parts.first ?? "" {
        case "import": importer.importFiles(arg.split(separator: "|").map { URL(fileURLWithPath: String($0)) })
        case "link": importer.importLink(arg)
        case "open":
            if let entry = books.first(where: { $0.id == arg || $0.book.title.localizedCaseInsensitiveContains(arg) }) { open(entry.id) }
        case "close": closeReader()
        case "next": reader?.nextPage()
        case "prev": reader?.previousPage()
        case "goto": if let f = Double(arg) { reader?.go(toFraction: f) }
        case "panel": reader?.panel = ReaderPanel(rawValue: arg)
        case "overlay": overlay = ShelfOverlay(rawValue: arg)
        case "theme": if let t = ReaderTheme(rawValue: arg) { settings.followsSystemAppearance = false; settings.theme = t }
        case "turn": if let t = PageTurn(rawValue: arg) { settings.pageTurn = t }
        case "focus": reader?.toggleFocus()
        case "snip": reader?.isSnipping.toggle()
        case "contents": reader?.showsContents.toggle()
        case "appearance": reader?.showsAppearance.toggle()
        case "select": reader?.debugSelect(arg)
        case "highlight": reader?.highlight(HighlightColor(rawValue: arg) ?? .yellow)
        case "glance": reader?.glance(Glance.Kind(rawValue: arg) ?? .explain)
        case "ask": reader?.chat.send(arg)
        case "asksel": reader?.askAboutSelection()
        case "rate": if let id = reader?.entry.id ?? books.first?.id { setRating(Int(arg), for: id) }
        case "status":
            let bits = arg.split(separator: "=", maxSplits: 1).map(String.init)
            if bits.count == 2, let e = books.first(where: { $0.book.title.localizedCaseInsensitiveContains(bits[0]) }), let s = ReadingStatus(rawValue: bits[1]) { setStatus(s, for: e.id) }
        case "onboard": hasOnboarded = arg != "reset"
        case "dump":
            DebugHooks.log("books=\(books.count) route=\(route) agents=\(agents.map(\.kind.rawValue)) reader.loading=\(String(describing: reader?.isLoading)) annotations=\(reader?.annotations.count ?? -1) fraction=\(reader?.fraction ?? -1) chat=\(reader?.chat.messages.last?.text.prefix(300) ?? "")")
        default: DebugHooks.log("unknown command: \(line)")
        }
    }
}
