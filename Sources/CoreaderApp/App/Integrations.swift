import AppKit
import CoreaderKit
import Foundation

/// The optional connections around the app: the `coreader` command, the agent skill,
/// and Mastisk. Each is a small, reversible change in the user's home folder.
enum Integrations {
    struct CommandResult: Sendable {
        var status: Int32
        var output: String
    }

    /// Runs a tool with a timeout and no shell. Output goes to a temporary file, not a
    /// pipe: a pipe stays open while any descendant of the tool holds it, and reading it
    /// to the end would then wait past the timeout.
    static func run(_ executable: URL, _ arguments: [String], timeout: TimeInterval = 20, environment: [String: String] = [:]) async -> CommandResult {
        await Task.detached { runBlocking(executable, arguments, timeout: timeout, environment: environment) }.value
    }

    private static func runBlocking(_ executable: URL, _ arguments: [String], timeout: TimeInterval, environment: [String: String]) -> CommandResult {
        do {
            let capture = FileManager.default.temporaryDirectory.appendingPathComponent("coreader-run-\(UUID().uuidString).txt")
            FileManager.default.createFile(atPath: capture.path, contents: nil)
            defer { try? FileManager.default.removeItem(at: capture) }
            guard let output = try? FileHandle(forWritingTo: capture) else { return CommandResult(status: -1, output: "") }
            let process = Process()
            process.executableURL = executable
            process.arguments = arguments
            if !environment.isEmpty { process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, new in new } }
            process.standardOutput = output
            process.standardError = output
            process.standardInput = FileHandle.nullDevice
            let finished = DispatchSemaphore(value: 0)
            process.terminationHandler = { _ in finished.signal() }
            do { try process.run() } catch { return CommandResult(status: -1, output: error.localizedDescription) }
            if finished.wait(timeout: .now() + timeout) == .timedOut {
                process.terminate()
                if finished.wait(timeout: .now() + 2) == .timedOut { kill(process.processIdentifier, SIGKILL) }
                return CommandResult(status: -2, output: "Timed out.")
            }
            try? output.close()
            let data = (try? Data(contentsOf: capture)) ?? Data()
            return CommandResult(status: process.terminationStatus, output: String(data: data.prefix(200_000), encoding: .utf8) ?? "")
        }
    }

    static var home: URL { FileManager.default.homeDirectoryForCurrentUser }

    // MARK: Command line tool

    static var bundledCLI: URL? {
        let url = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/coreader")
        return FileManager.default.isExecutableFile(atPath: url.path) ? url : nil
    }

    static var cliLink: URL { home.appendingPathComponent(".local/bin/coreader") }

    static var isCLIInstalled: Bool {
        guard let target = try? FileManager.default.destinationOfSymbolicLink(atPath: cliLink.path) else { return false }
        return FileManager.default.isExecutableFile(atPath: target)
    }

    /// Links `~/.local/bin/coreader` to the copy inside the app, so it updates with the app.
    static func installCLI() throws {
        guard let cli = bundledCLI else { throw Problem("This build does not include the command line tool.") }
        // A link into a disk image or a quarantine copy breaks when it is ejected.
        let location = Bundle.main.bundlePath
        guard !location.hasPrefix("/Volumes/"), !location.contains("/AppTranslocation/") else {
            throw Problem("Move Coreader to the Applications folder first, then install the command.")
        }
        let fm = FileManager.default
        try fm.createDirectory(at: cliLink.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let target = try? fm.destinationOfSymbolicLink(atPath: cliLink.path) {
            guard target.hasSuffix("/Contents/Helpers/coreader") else { throw Problem("\(cliLink.path) is a link to something else. Remove it first.") }
            try fm.removeItem(at: cliLink)
        }
        guard !fm.fileExists(atPath: cliLink.path) else { throw Problem("\(cliLink.path) already exists and is not a link Coreader made.") }
        try fm.createSymbolicLink(at: cliLink, withDestinationURL: cli)
    }

    // MARK: Agent skill

    static var bundledSkill: URL? {
        let url = Bundle.main.resourceURL?.appendingPathComponent("skill/coreader")
        return url.flatMap { FileManager.default.fileExists(atPath: $0.appendingPathComponent("SKILL.md").path) ? $0 : nil }
    }

    /// Folders where agent CLIs look for skills, limited to the tools present here.
    static var skillHomes: [URL] {
        [".claude", ".codex", ".agents"].map { home.appendingPathComponent($0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
            .map { $0.appendingPathComponent("skills") }
    }

    static var isSkillInstalled: Bool {
        !skillHomes.isEmpty && skillHomes.allSatisfy { FileManager.default.fileExists(atPath: $0.appendingPathComponent("coreader/SKILL.md").path) }
    }

    static func installSkill() throws {
        guard let skill = bundledSkill else { throw Problem("This build does not include the agent skill.") }
        guard !skillHomes.isEmpty else { throw Problem("No agent folders (~/.claude, ~/.codex, ~/.agents) were found.") }
        for home in skillHomes { try copySkill(from: skill, named: "coreader", into: home) }
    }

    /// Marker left in every skill folder Coreader installs, so it only ever replaces its own.
    static let skillMarker = ".installed-by-coreader"

    /// Copies a skill folder into a skills directory. An existing folder of the same name
    /// is replaced only if Coreader installed it; a skill the user wrote by hand is left
    /// alone and the install fails with an explanation. The new copy is staged first, so
    /// a failed copy never leaves the old one gone.
    static func copySkill(from source: URL, named name: String, into skills: URL) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: skills, withIntermediateDirectories: true)
        let target = skills.appendingPathComponent(name)
        let exists = fm.fileExists(atPath: target.path) || (try? fm.destinationOfSymbolicLink(atPath: target.path)) != nil
        if exists, !fm.fileExists(atPath: target.appendingPathComponent(skillMarker).path) {
            throw Problem("A skill named “\(name)” already exists in \(skills.path) and was not installed by Coreader. Rename or remove it first.")
        }
        let staged = skills.appendingPathComponent(".\(name).coreader-staging")
        try? fm.removeItem(at: staged)
        try fm.copyItem(at: source, to: staged)
        fm.createFile(atPath: staged.appendingPathComponent(skillMarker).path, contents: nil)
        if exists {
            _ = try fm.replaceItemAt(target, withItemAt: staged)
        } else {
            try fm.moveItem(at: staged, to: target)
        }
    }

    // MARK: Mastisk

    enum MastiskState: Equatable {
        /// No Mastisk on this Mac or on the person's tailnet.
        case notFound
        /// Mastisk was found but lacks the Coreader connector. `host` is nil for this Mac.
        case needsConnector(host: String?)
        /// Mastisk on this Mac, connector off: Coreader can switch it on.
        case disconnected
        /// Mastisk on this Mac indexes another folder than this library; connecting again fixes it.
        case localOtherFolder
        case connected(books: Int, host: String?)
        /// Mastisk on another machine with the connector off: it has to be switched on there.
        case remoteOff(host: String)
        /// Mastisk on another machine reads a different folder, so it cannot see this library.
        case remoteOtherFolder(host: String)
        case unknown(String)
    }

    static var mastiskCLI: URL? {
        let candidates = [home.appendingPathComponent(".local/bin/mastisk"), URL(fileURLWithPath: "/opt/homebrew/bin/mastisk"), URL(fileURLWithPath: "/usr/local/bin/mastisk")]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    static var tailscaleCLI: URL? {
        let candidates = ["/Applications/Tailscale.app/Contents/MacOS/Tailscale", "/opt/homebrew/bin/tailscale", "/usr/local/bin/tailscale"]
        return candidates.map { URL(fileURLWithPath: $0) }.first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    /// Last Mastisk address that answered, so the next check does not need Tailscale.
    private static let rememberedMastiskKey = "mastiskURL"

    private static let mastiskSession: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 3
        config.timeoutIntervalForResource = 5
        config.httpCookieStorage = nil
        return URLSession(configuration: config, delegate: NoRedirects(), delegateQueue: nil)
    }()

    /// A probed host must answer itself; following a redirect would let it point the
    /// app at an address that was never on the list.
    private final class NoRedirects: NSObject, URLSessionTaskDelegate {
        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
            completionHandler(nil)
        }
    }

    /// `COREADER_MASTISK_LOCAL` points the "this Mac" check elsewhere, for off-screen runs.
    private static let mastiskLocator = MastiskLocator(local: ProcessInfo.processInfo.environment["COREADER_MASTISK_LOCAL"].flatMap(URL.init(string:)) ?? MastiskLocator.localURL) { url in
        guard let (data, response) = try? await mastiskSession.data(from: url), let http = response as? HTTPURLResponse else { return nil }
        return (status: http.statusCode, body: data.prefix(100_000))
    }

    /// Looks on this Mac first, then on the tailnet. Read-only: nothing is switched on.
    static func mastiskState(libraryRoot: URL) async -> MastiskState {
        let defaults = UserDefaults.standard
        let remembered = defaults.string(forKey: rememberedMastiskKey).flatMap(URL.init(string:))
        var found = await mastiskLocator.locate(remembered: remembered, tailscaleStatus: nil)
        if found == nil, let tailscale = tailscaleCLI {
            // The app's own binary is both GUI and CLI; without this it can open the GUI.
            let status = await run(tailscale, ["status", "--json"], timeout: 6, environment: ["TAILSCALE_BE_CLI": "1"])
            if status.status == 0 { found = await mastiskLocator.locate(remembered: nil, tailscaleStatus: status.output.data(using: .utf8)) }
        }
        guard let found else {
            defaults.removeObject(forKey: rememberedMastiskKey)
            // Installed here but not running: the command still knows the connector's state.
            return mastiskCLI == nil ? .notFound : await mastiskStateFromCLI()
        }
        if found.isLocal {
            guard let connector = found.connector else { return .needsConnector(host: nil) }
            guard connector.enabled else { return .disconnected }
            return MastiskLocator.sameFolder(connector.libraryRoot, libraryRoot.path) ? .connected(books: connector.books, host: nil) : .localOtherFolder
        }
        defaults.set(found.baseURL.absoluteString, forKey: rememberedMastiskKey)
        let host = found.baseURL.host?.components(separatedBy: ".").first ?? "another machine"
        guard let connector = found.connector else { return .needsConnector(host: host) }
        guard connector.enabled else { return .remoteOff(host: host) }
        guard MastiskLocator.sharesLibrary(local: libraryRoot.path, remote: connector.libraryRoot) else { return .remoteOtherFolder(host: host) }
        return .connected(books: connector.books, host: host)
    }

    private static func mastiskStateFromCLI() async -> MastiskState {
        guard let cli = mastiskCLI else { return .notFound }
        let result = await run(cli, ["coreader", "status", "--json"], timeout: 15)
        if result.status == 2 || result.output.contains("No such command") { return .needsConnector(host: nil) }
        guard result.status == 0, let data = result.output.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .unknown("Mastisk is installed but did not answer.")
        }
        if json["enabled"] as? Bool == true { return .connected(books: json["books"] as? Int ?? 0, host: nil) }
        return .disconnected
    }

    /// Switches the connector on this Mac's Mastisk on or off, through its own command.
    static func connectMastisk(_ connect: Bool, libraryRoot: URL) async -> MastiskState {
        guard let cli = mastiskCLI else { return .unknown("The mastisk command was not found on this Mac.") }
        let result = await run(cli, ["coreader", connect ? "connect" : "disconnect", "--json"], timeout: 30)
        let state = await mastiskState(libraryRoot: libraryRoot)
        if result.status != 0 {
            // A slow first scan can outlast the timeout after the setting was already
            // written, so what Mastisk now says wins over the command's exit code.
            let settled = connect ? { if case .connected = state { return true } else { return false } }() : state == .disconnected
            if !settled { return .unknown(result.output.trimmingCharacters(in: .whitespacesAndNewlines).prefix(200).description) }
        }
        return state
    }

    struct Problem: LocalizedError {
        var message: String
        init(_ message: String) { self.message = message }
        var errorDescription: String? { message }
    }
}
