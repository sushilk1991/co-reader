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
        // Try direct paths first (faster than spawning a shell)
        for path in Self.commonClaudePaths {
            if FileManager.default.isExecutableFile(atPath: path) {
                do {
                    let result = try await commandRunner.run(versionCommand(executable: path, arguments: ["--version"]))
                    if result.exitCode == 0 {
                        let version = result.standardOutput
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                            .split(separator: "\n")
                            .first
                            .map(String.init) ?? "available"
                        return .available(version: version.isEmpty ? "available" : version)
                    }
                } catch let error as ShellCommandError {
                    // A hung binary will not be rescued by the login-shell fallback.
                    return .unavailable(reason: error.localizedDescription)
                } catch {
                    continue
                }
            }
        }

        // Fallback: try via login shell to get full PATH
        do {
            let result = try await commandRunner.run(
                versionCommand(executable: "/bin/zsh", arguments: ["-l", "-c", "claude --version"])
            )
            if result.exitCode == 0 {
                let version = result.standardOutput
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .split(separator: "\n")
                    .first
                    .map(String.init) ?? "available"
                return .available(version: version.isEmpty ? "available" : version)
            }
        } catch let error as ShellCommandError {
            return .unavailable(reason: error.localizedDescription)
        } catch {}

        return .unavailable(reason: "claude not found on PATH")
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
