import AppKit
import CoreaderKit
import Security

/// Finds a newer Coreader on GitHub, and on request downloads it, checks that it was
/// signed by the same developer as the copy that is running, swaps it in and relaunches.
@MainActor
@Observable
final class Updater {
    enum Phase: Equatable {
        case idle
        case checking
        case upToDate
        case available(AppRelease)
        case downloading(AppRelease, fraction: Double)
        case installing(AppRelease)
        case failed(String, page: URL?)
    }

    private(set) var phase: Phase = .idle
    /// The update sheet. Shown for a check the person asked for, and when a check made at
    /// launch finds something.
    var isPresented = false

    var checksAutomatically: Bool = UserDefaults.standard.object(forKey: Keys.automatic) as? Bool ?? true {
        didSet { UserDefaults.standard.set(checksAutomatically, forKey: Keys.automatic) }
    }

    static let repository = "sushilk1991/co-reader"
    private enum Keys {
        static let automatic = "updates.automatic", lastCheck = "updates.lastCheck", skipped = "updates.skippedVersion"
    }

    var currentVersion: AppVersion? {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String).flatMap(AppVersion.init)
    }

    private var work: Task<Void, Never>?

    // MARK: Checking

    /// At launch: at most once a day, silent unless there is something new that the person
    /// has not already declined.
    func checkAtLaunch() {
        guard checksAutomatically, !DebugHooks.isOffscreen else { return }
        let last = UserDefaults.standard.double(forKey: Keys.lastCheck)
        guard Date().timeIntervalSince1970 - last > 20 * 3600 else { return }
        check(byRequest: false)
    }

    func check(byRequest: Bool) {
        if case .downloading = phase { isPresented = true; return }
        if case .installing = phase { isPresented = true; return }
        work?.cancel()
        if byRequest { phase = .checking; isPresented = true }
        work = Task {
            let result = await Self.fetchLatest()
            guard !Task.isCancelled else { return }
            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: Keys.lastCheck)
            switch result {
            case .success(let release):
                guard let current = currentVersion, current < release.version else {
                    phase = byRequest ? .upToDate : .idle
                    return
                }
                if !byRequest, UserDefaults.standard.string(forKey: Keys.skipped) == release.version.description { return }
                phase = .available(release)
                isPresented = true
            case .failure(let problem):
                // A check nobody asked for fails quietly: no network is not news.
                phase = byRequest ? .failed(problem.message, page: Self.releasesPage) : .idle
            }
        }
    }

    func skip(_ release: AppRelease) {
        UserDefaults.standard.set(release.version.description, forKey: Keys.skipped)
        dismiss()
    }

    func dismiss() {
        isPresented = false
        switch phase {
        case .downloading, .installing: break   // keeps going; the menu item brings the sheet back
        default: phase = .idle
        }
    }

    func cancelDownload() {
        work?.cancel()
        phase = .idle
        isPresented = false
    }

    static var releasesPage: URL { URL(string: "https://github.com/\(repository)/releases/latest")! }

    private struct Problem: Error { var message: String }

    private static func fetchLatest() async -> Result<AppRelease, Problem> {
        let url = URL(string: "https://api.github.com/repos/\(repository)/releases/latest")!
        func get(token: String?) async -> (Data, Int)? {
            var request = URLRequest(url: url, timeoutInterval: 20)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
            guard let (data, response) = try? await URLSession.shared.data(for: request) else { return nil }
            return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        guard var answer = await get(token: nil) else {
            return .failure(Problem(message: "Could not reach GitHub. Check your connection and try again."))
        }
        // While the repository is private GitHub answers 404 to strangers; a signed-in
        // GitHub command line tool on this Mac can vouch for us.
        if answer.1 != 200, let token = await gitHubToken(), let retry = await get(token: token) { answer = retry }
        guard answer.1 == 200 else {
            return .failure(Problem(message: answer.1 == 404 || answer.1 == 401 || answer.1 == 403
                ? "GitHub would not show the releases. Coreader's repository is private: sign in with the GitHub command line tool (gh auth login), or download the update from the releases page."
                : "GitHub answered with an error (\(answer.1)). Try again later."))
        }
        guard let release = AppRelease.parse(gitHubJSON: answer.0) else {
            return .failure(Problem(message: "The latest release has no download for Mac yet."))
        }
        return .success(release)
    }

    /// The token of a signed-in `gh`, if there is one. Sent only to api.github.com.
    private static func gitHubToken() async -> String? {
        let candidates = ["/opt/homebrew/bin/gh", "/usr/local/bin/gh", "/usr/bin/gh"]
        guard let gh = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else { return nil }
        let result = await Integrations.run(URL(fileURLWithPath: gh), ["auth", "token"], timeout: 8)
        let token = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        return result.status == 0 && !token.isEmpty && !token.contains(" ") ? token : nil
    }

    // MARK: Installing

    func install(_ release: AppRelease) {
        work?.cancel()
        phase = .downloading(release, fraction: 0)
        isPresented = true
        work = Task {
            do {
                let destination = try Self.installDestination()
                let team = try Self.ownTeam()
                let folder = FileManager.default.temporaryDirectory.appendingPathComponent("coreader-update-\(UUID().uuidString)")
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                defer { try? FileManager.default.removeItem(at: folder) }

                let image = folder.appendingPathComponent("Coreader.dmg")
                try await Self.download(release, to: image) { [weak self] fraction in
                    Task { @MainActor in
                        if case .downloading(let r, _) = self?.phase, r == release { self?.phase = .downloading(release, fraction: fraction) }
                    }
                }
                try Task.checkCancellation()
                phase = .installing(release)

                let staged = try await Self.stage(image: image, in: folder, team: team, newerThan: currentVersion, beside: destination)
                try Task.checkCancellation()
                try Self.swapAfterQuit(staged: staged, destination: destination)
                try? FileManager.default.removeItem(at: folder)   // `defer` does not run once the app exits
                // The sheet first: an app with a sheet up does not act on a request to quit.
                isPresented = false
                try? await Task.sleep(for: .milliseconds(700))
                NSApp.terminate(nil)
                // The swap is waiting on this process. If quitting was held up by some
                // other window, finish the pending writes and leave anyway.
                try? await Task.sleep(for: .seconds(5))
                await WriteQueue.shared.drain()
                exit(0)
            } catch is CancellationError {
                // Cancelled by the person; nothing to say.
            } catch {
                phase = .failed((error as? Problem)?.message ?? error.localizedDescription, page: release.page)
                isPresented = true
            }
        }
    }

    /// Where the running app lives, if it can be replaced there.
    private static func installDestination() throws -> URL {
        let app = Bundle.main.bundleURL
        let path = app.path
        guard app.pathExtension == "app", !path.hasPrefix("/Volumes/"), !path.contains("/AppTranslocation/") else {
            throw Problem(message: "Move Coreader into your Applications folder first, then update. It is running from a disk image or a temporary location.")
        }
        guard FileManager.default.isWritableFile(atPath: app.deletingLastPathComponent().path) else {
            throw Problem(message: "Coreader cannot replace itself in \(app.deletingLastPathComponent().path). Download the update and drag it there yourself.")
        }
        return app
    }

    /// The Apple developer team that signed the running app. An update must carry the same.
    private static func ownTeam() throws -> String {
        var code: SecStaticCode?
        var info: CFDictionary?
        guard SecStaticCodeCreateWithPath(Bundle.main.bundleURL as CFURL, [], &code) == errSecSuccess, let code,
              SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let team = (info as? [String: Any])?[kSecCodeInfoTeamIdentifier as String] as? String, !team.isEmpty else {
            throw Problem(message: "This copy of Coreader is a development build, which cannot update itself. Download the release instead.")
        }
        return team
    }

    private static func download(_ release: AppRelease, to file: URL, progress: @escaping @Sendable (Double) -> Void) async throws {
        var request = URLRequest(url: release.asset, timeoutInterval: 60)
        request.setValue("application/octet-stream", forHTTPHeaderField: "Accept")
        if let token = await gitHubToken() { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        let watcher = DownloadWatcher(progress: progress)
        let (temporary, response) = try await URLSession.shared.download(for: request, delegate: watcher)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw Problem(message: "The download failed (\((response as? HTTPURLResponse)?.statusCode ?? 0)).")
        }
        try FileManager.default.moveItem(at: temporary, to: file)
        if release.size > 0, let size = try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize, size != release.size {
            throw Problem(message: "The download was incomplete. Try again.")
        }
    }

    /// Opens the disk image, checks the app inside, and copies it next to the running one
    /// (same disk, so the final swap is a rename). Returns the copy.
    private static func stage(image: URL, in folder: URL, team: String, newerThan current: AppVersion?, beside destination: URL) async throws -> URL {
        let mount = folder.appendingPathComponent("mount")
        let hdiutil = URL(fileURLWithPath: "/usr/bin/hdiutil")
        let attached = await Integrations.run(hdiutil, ["attach", image.path, "-nobrowse", "-readonly", "-noautoopen", "-mountpoint", mount.path], timeout: 120)
        guard attached.status == 0 else { throw Problem(message: "The downloaded update could not be opened.") }
        var stagedOK = false
        let staged = destination.deletingLastPathComponent().appendingPathComponent(".Coreader-update-\(UUID().uuidString).app")
        defer { if !stagedOK { try? FileManager.default.removeItem(at: staged) } }
        do {
            let fresh = mount.appendingPathComponent(destination.lastPathComponent)
            guard FileManager.default.fileExists(atPath: fresh.path) else { throw Problem(message: "The update does not contain Coreader.") }
            try verify(fresh, team: team)
            guard let version = (Bundle(url: fresh)?.infoDictionary?["CFBundleShortVersionString"] as? String).flatMap(AppVersion.init),
                  current.map({ $0 < version }) ?? true else {
                throw Problem(message: "The download is not newer than the version you have.")
            }
            let copied = await Integrations.run(URL(fileURLWithPath: "/usr/bin/ditto"), [fresh.path, staged.path], timeout: 180)
            guard copied.status == 0 else { throw Problem(message: "The update could not be copied into place.") }
            // Checked again where it will run from: what was verified is what gets launched.
            try verify(staged, team: team)
        } catch {
            _ = await Integrations.run(hdiutil, ["detach", mount.path, "-force"], timeout: 30)
            throw error
        }
        _ = await Integrations.run(hdiutil, ["detach", mount.path, "-force"], timeout: 30)
        stagedOK = true
        return staged
    }

    /// The whole bundle must be intact, be Coreader, and be signed by Apple-issued
    /// certificates of the given team. That is the only thing standing between a tampered
    /// download and running it, so it is strict.
    private static func verify(_ app: URL, team: String) throws {
        let rule = "identifier \"\(Bundle.main.bundleIdentifier ?? "com.sushil.coreader")\" and anchor apple generic and certificate leaf[subject.OU] = \"\(team)\""
        var code: SecStaticCode?
        var requirement: SecRequirement?
        guard SecStaticCodeCreateWithPath(app as CFURL, [], &code) == errSecSuccess, let code,
              SecRequirementCreateWithString(rule as CFString, [], &requirement) == errSecSuccess, let requirement else {
            throw Problem(message: "The update's signature could not be read.")
        }
        let flags = SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSCheckNestedCode | kSecCSStrictValidate)
        guard SecStaticCodeCheckValidity(code, flags, requirement) == errSecSuccess else {
            throw Problem(message: "The update was not signed by Coreader's developer, so it was not installed.")
        }
    }

    /// Leaves a small script waiting for this app to quit; it then renames the new copy
    /// into place and opens it. If the rename fails the old app is put back.
    private static func swapAfterQuit(staged: URL, destination: URL) throws {
        let script = """
        while kill -0 "$1" 2>/dev/null; do sleep 0.2; done
        old="$3.old-$$"
        if mv "$3" "$old" && mv "$2" "$3"; then rm -rf "$old"; else [ -e "$3" ] || mv "$old" "$3"; rm -rf "$2"; fi
        open $4 "$3"
        """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        // Unattended test runs reopen in the background, as they started.
        process.arguments = ["-c", script, "sh", String(ProcessInfo.processInfo.processIdentifier), staged.path, destination.path,
                             DebugHooks.isOffscreen ? "-gj" : "-n"]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch {
            try? FileManager.default.removeItem(at: staged)
            throw Problem(message: "The update could not be started.")
        }
    }
}

/// Reports download progress, and keeps the GitHub token from following a redirect to
/// the storage host that actually serves the file.
private final class DownloadWatcher: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let progress: @Sendable (Double) -> Void
    private var observation: NSKeyValueObservation?

    init(progress: @escaping @Sendable (Double) -> Void) { self.progress = progress }

    func urlSession(_ session: URLSession, didCreateTask task: URLSessionTask) {
        let report = progress
        observation = task.progress.observe(\.fractionCompleted) { value, _ in report(value.fractionCompleted) }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        var next = request
        if request.url?.host != task.originalRequest?.url?.host { next.setValue(nil, forHTTPHeaderField: "Authorization") }
        completionHandler(next.url?.scheme == "https" ? next : nil)
    }
}
