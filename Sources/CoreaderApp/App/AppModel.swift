import AppKit
import CoreaderKit
import SwiftUI

/// Runs blocking library work off the main actor.
func background<T: Sendable>(_ work: @escaping @Sendable () throws -> T) async throws -> T {
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
            books = try await background {
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
        if let all = try? await background({ try library.allBooks() }) { books = all }
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
            do { try await background { try library.save(entry.book, in: entry.folder) } }
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
            do { try await background { try library.delete(id: id) } }
            catch { show("Could not remove “\(entry.book.title)”.", isError: true) }
            show("Moved “\(entry.book.title)” to the Trash.")
        }
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
