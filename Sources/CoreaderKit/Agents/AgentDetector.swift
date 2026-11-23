import Foundation
import Synchronization

/// Finds the agent CLIs installed on this Mac.
///
/// An app launched from Finder gets launchd's PATH, not the shell's, so the
/// search uses the login shell's PATH (asked once) plus the directories the
/// CLIs' installers use.
public struct AgentDetector: Sendable {
    /// `nil` skips asking a shell.
    var loginShell: URL?
    var wellKnownDirectories: [URL]
    var probeTimeout: Duration

    public init() {
        self.init(
            loginShell: AgentEnvironment.loginShell,
            wellKnownDirectories: AgentEnvironment.wellKnownDirectories,
            probeTimeout: .seconds(5)
        )
    }

    init(loginShell: URL?, wellKnownDirectories: [URL], probeTimeout: Duration) {
        self.loginShell = loginShell
        self.wellKnownDirectories = wellKnownDirectories
        self.probeTimeout = probeTimeout
    }

    /// Never hangs: each probe is killed after `probeTimeout`.
    public func detect() async -> [DetectedAgent] {
        #if os(macOS)
        let directories = await searchDirectories()
        return await withTaskGroup(of: DetectedAgent?.self) { group in
            for kind in AgentKind.allCases {
                group.addTask {
                    guard let executable = Self.locate(kind.executableName, in: directories) else { return nil }
                    return DetectedAgent(kind: kind, executable: executable, version: await version(of: executable))
                }
            }
            var found: [DetectedAgent] = []
            for await agent in group { if let agent { found.append(agent) } }
            return AgentKind.allCases.compactMap { kind in found.first { $0.kind == kind } }
        }
        #else
        return []
        #endif
    }

    static func locate(_ name: String, in directories: [URL]) -> URL? {
        for directory in directories {
            let candidate = directory.appendingPathComponent(name)
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: candidate.path, isDirectory: &isDirectory), !isDirectory.boolValue,
               FileManager.default.isExecutableFile(atPath: candidate.path) {
                return candidate
            }
        }
        return nil
    }

    /// "2.1.330 (Claude Code)", "codex-cli 0.170.0" and "1.5.13" all yield the number.
    static func parseVersion(_ output: String) -> String? {
        for line in output.split(separator: "\n") {
            if let match = line.range(of: #"\d+(\.\d+)+([-+][0-9A-Za-z.]+)?"#, options: .regularExpression) {
                return String(line[match])
            }
        }
        return nil
    }

    /// The `PATH=` line of `env` output. Shell startup files may print
    /// anything before it, so the last match wins.
    static func parsePath(fromEnvironmentListing output: String) -> [URL] {
        guard let line = output.split(separator: "\n").last(where: { $0.hasPrefix("PATH=") }) else { return [] }
        return line.dropFirst("PATH=".count).split(separator: ":").filter { $0.hasPrefix("/") }
            .map { URL(fileURLWithPath: String($0)) }
    }

    #if os(macOS)
    private func searchDirectories() async -> [URL] {
        var directories = await loginShellPath()
        for directory in wellKnownDirectories where !directories.contains(directory) {
            directories.append(directory)
        }
        return directories
    }

    private func loginShellPath() async -> [URL] {
        guard let loginShell else { return [] }
        if let cached = AgentEnvironment.cachedShellPath(for: loginShell) { return cached }
        // `command -v claude` would be simpler, but it prints alias text when
        // the reader has aliased the CLI (commonly to add permission-skipping
        // flags), and `whence -p` is zsh-only. `/usr/bin/env` is a plain
        // binary: same output from zsh, bash and fish, and no alias applies.
        let spec = AgentProcessSpec(
            executable: loginShell, arguments: ["-ilc", "/usr/bin/env"],
            environment: ProcessInfo.processInfo.environment,
            idleTimeout: probeTimeout, totalTimeout: probeTimeout
        )
        guard let result = try? await AgentProcess.capture(spec) else { return [] }
        let path = Self.parsePath(fromEnvironmentListing: result.stdout)
        if !path.isEmpty { AgentEnvironment.cacheShellPath(path, for: loginShell) }
        return path
    }

    private func version(of executable: URL) async -> String? {
        let spec = AgentProcessSpec(
            executable: executable, arguments: ["--version"],
            environment: AgentEnvironment.environment(for: executable),
            idleTimeout: probeTimeout, totalTimeout: probeTimeout
        )
        guard let result = try? await AgentProcess.capture(spec), result.exitCode == 0 else { return nil }
        return Self.parseVersion(result.stdout) ?? Self.parseVersion(result.stderr)
    }
    #endif
}

/// The environment agent CLIs are started with.
enum AgentEnvironment {
    private static let shellPaths = Mutex<[URL: [URL]]>([:])

    static var loginShell: URL? {
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        return FileManager.default.isExecutableFile(atPath: shell) ? URL(fileURLWithPath: shell) : nil
    }

    static var wellKnownDirectories: [URL] {
        let home = URL(fileURLWithPath: NSHomeDirectory())
        let user = NSUserName()
        return [
            home.appendingPathComponent(".local/bin"),
            URL(fileURLWithPath: "/opt/homebrew/bin"),
            URL(fileURLWithPath: "/usr/local/bin"),
            home.appendingPathComponent(".claude/local"),
            home.appendingPathComponent(".npm-global/bin"),
            home.appendingPathComponent(".bun/bin"),
            home.appendingPathComponent(".cargo/bin"),
            home.appendingPathComponent(".nix-profile/bin"),
            URL(fileURLWithPath: "/etc/profiles/per-user/\(user)/bin"),
            URL(fileURLWithPath: "/run/current-system/sw/bin"),
            URL(fileURLWithPath: "/nix/var/nix/profiles/default/bin"),
        ]
    }

    static func cachedShellPath(for shell: URL) -> [URL]? { shellPaths.withLock { $0[shell] } }
    static func cacheShellPath(_ path: [URL], for shell: URL) { shellPaths.withLock { $0[shell] = path } }

    /// The app's environment with a PATH on which the CLI finds its helpers
    /// (node, git, ripgrep): its own directory, the login shell's PATH when
    /// the detector has learned it, the usual install directories, the system's.
    static func environment(for executable: URL) -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        var path: [String] = [executable.deletingLastPathComponent().path]
        let add: (String) -> Void = { if !$0.isEmpty, !path.contains($0) { path.append($0) } }
        shellPaths.withLock { $0.values.joined().forEach { add($0.path) } }
        wellKnownDirectories.forEach { add($0.path) }
        (environment["PATH"] ?? "").split(separator: ":").forEach { add(String($0)) }
        ["/usr/bin", "/bin", "/usr/sbin", "/sbin"].forEach(add)
        environment["PATH"] = path.joined(separator: ":")
        // Output is parsed, never shown in a terminal.
        environment["NO_COLOR"] = "1"
        environment["TERM"] = "dumb"
        return environment
    }
}
