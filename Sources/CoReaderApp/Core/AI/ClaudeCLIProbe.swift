import Foundation

struct ClaudeCLIProbe: ClaudeCLIProbing {
    let commandRunner: ShellCommandRunning

    init(commandRunner: ShellCommandRunning = ProcessCommandRunner()) {
        self.commandRunner = commandRunner
    }

    /// `claude --version` normally returns in well under a second; a login shell adds
    /// dotfile start-up on top.
    static let probeTimeout: Duration = .seconds(15)

    func probe() async throws -> AIProviderProbeResult {
        do {
            return .available(version: try await resolve().version)
        } catch {
            return .unavailable(reason: error.localizedDescription)
        }
    }

    /// Probe and generation share one resolution path, including GUI launches with a minimal PATH.
    /// `common executable -> version check -> login shell fallback -> requested command`.
    func runResolved(
        arguments: [String],
        standardInput: String,
        timeout: Duration
    ) async throws -> ShellCommandResult {
        let resolved = try await resolve()
        return try await commandRunner.run(ShellCommand(
            executable: resolved.executable,
            arguments: resolved.prefix + arguments,
            standardInput: standardInput,
            timeout: timeout
        ))
    }

    /// Preserve the probe's path order; shell arguments travel as positional parameters, never interpolated code.
    private func resolve() async throws -> (executable: String, prefix: [String], version: String) {
        for path in Self.commonClaudePaths {
            guard FileManager.default.isExecutableFile(atPath: path) else {
                continue
            }

            do {
                let result = try await commandRunner.run(versionCommand(executable: path, arguments: ["--version"]))
                if result.exitCode == EXIT_SUCCESS {
                    return (path, [], version(from: result))
                }
            } catch let error as ShellCommandError {
                // A hung binary will not be rescued by the login-shell fallback.
                throw error
            } catch {
                continue
            }
        }

        // Reuse the login shell for generation so its PATH matches the successful probe.
        do {
            let result = try await commandRunner.run(
                versionCommand(executable: "/bin/zsh", arguments: ["-l", "-c", "claude --version"])
            )
            if result.exitCode == EXIT_SUCCESS {
                return ("/bin/zsh", ["-l", "-c", "exec claude \"$@\"", "claude"], version(from: result))
            }
        } catch let error as ShellCommandError {
            throw error
        } catch {}

        throw ClaudeResolutionError.notFound
    }

    /// Match the availability pill's existing version formatting for either resolution path.
    private func version(from result: ShellCommandResult) -> String {
        let version = result.standardOutput
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: "\n")
            .first
            .map(String.init) ?? "available"
        return version.isEmpty ? "available" : version
    }

    private func versionCommand(executable: String, arguments: [String]) -> ShellCommand {
        ShellCommand(
            executable: executable,
            arguments: arguments,
            standardInput: nil,
            timeout: Self.probeTimeout
        )
    }

    private static let commonClaudePaths: [String] = {
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

/// Give both callers a readable failure when no installed CLI passes the probe.
private enum ClaudeResolutionError: LocalizedError {
    case notFound

    var errorDescription: String? {
        "claude not found on PATH"
    }
}
