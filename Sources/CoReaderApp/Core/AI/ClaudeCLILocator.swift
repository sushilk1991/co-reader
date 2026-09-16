import Foundation

/// Finds the `claude` binary once per app session so the probe and generation
/// both spawn it directly. A GUI launch inherits a minimal PATH, so the login
/// shell is consulted only to *locate* the binary, never to run it: dotfile
/// output can then never share a pipe with an answer.
///
/// ```
///  executablePath()
///     ├─ stored path ─────────────────────────────▶ return
///     ├─ common install paths (file check only) ──▶ store, return
///     └─ /bin/zsh -l -c 'command -v claude' ──────▶ last line, store, return
/// ```
actor ClaudeCLILocator {
    static let shared = ClaudeCLILocator()

    /// Dotfile start-up is the only cost here; `command -v` itself is instant.
    static let loginShellTimeout: Duration = .seconds(15)

    private let commandRunner: ShellCommandRunning
    private let commonPaths: [String]
    private var resolvedPath: String?

    init(
        commandRunner: ShellCommandRunning = ProcessCommandRunner(),
        commonPaths: [String] = ClaudeCLILocator.defaultCommonPaths
    ) {
        self.commandRunner = commandRunner
        self.commonPaths = commonPaths
    }

    /// Only a successful resolution is stored, so installing the CLI mid-session is picked up on the next call.
    func executablePath() async throws -> String {
        if let resolvedPath {
            return resolvedPath
        }

        let path = try await locate()
        resolvedPath = path
        return path
    }

    private func locate() async throws -> String {
        if let path = commonPaths.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
            return path
        }

        // Dotfiles may print before `command -v` does, so the path is the last line, not the first.
        let result = try await commandRunner.run(ShellCommand(
            executable: "/bin/zsh",
            arguments: ["-l", "-c", "command -v claude"],
            standardInput: nil,
            timeout: Self.loginShellTimeout
        ))
        guard result.exitCode == EXIT_SUCCESS,
              let path = result.standardOutput
                .split(whereSeparator: \.isNewline)
                .last
                .map({ $0.trimmingCharacters(in: .whitespaces) }),
              path.hasPrefix("/") else {
            throw ClaudeResolutionError.notFound
        }

        return path
    }

    private static let defaultCommonPaths: [String] = {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return [
            "\(home)/.claude/local/bin/claude",
            "/usr/local/bin/claude",
            "/opt/homebrew/bin/claude",
            "\(home)/.npm-global/bin/claude",
            "\(home)/.nvm/versions/node/default/bin/claude",
        ]
    }()
}

/// Give both callers a readable failure when no installed CLI can be located.
private enum ClaudeResolutionError: LocalizedError {
    case notFound

    var errorDescription: String? {
        "claude not found on PATH"
    }
}
