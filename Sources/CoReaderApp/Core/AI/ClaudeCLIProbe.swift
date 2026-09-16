import Foundation

struct ClaudeCLIProbe: ClaudeCLIProbing {
    let locator: ClaudeCLILocator
    let commandRunner: ShellCommandRunning

    init(
        locator: ClaudeCLILocator = .shared,
        commandRunner: ShellCommandRunning = ProcessCommandRunner()
    ) {
        self.locator = locator
        self.commandRunner = commandRunner
    }

    /// `claude --version` normally returns in well under a second.
    static let probeTimeout: Duration = .seconds(15)

    func probe() async throws -> AIProviderProbeResult {
        do {
            let result = try await commandRunner.run(ShellCommand(
                executable: try await locator.executablePath(),
                arguments: ["--version"],
                standardInput: nil,
                timeout: Self.probeTimeout
            ))
            guard result.exitCode == EXIT_SUCCESS else {
                return .unavailable(reason: failureReason(from: result))
            }

            return .available(version: version(from: result))
        } catch {
            return .unavailable(reason: error.localizedDescription)
        }
    }

    private func version(from result: ShellCommandResult) -> String {
        let version = result.standardOutput
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: "\n")
            .first
            .map(String.init) ?? "available"
        return version.isEmpty ? "available" : version
    }

    private func failureReason(from result: ShellCommandResult) -> String {
        let stderr = result.standardError.trimmingCharacters(in: .whitespacesAndNewlines)
        return stderr.isEmpty ? "claude --version exited with code \(result.exitCode)." : stderr
    }
}
