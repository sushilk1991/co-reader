import Foundation

struct ClaudeCLIProbe: ClaudeCLIProbing {
    let commandRunner: ShellCommandRunning

    init(commandRunner: ShellCommandRunning = ProcessCommandRunner()) {
        self.commandRunner = commandRunner
    }

    func probe() async throws -> AIProviderProbeResult {
        do {
            let result = try await commandRunner.run(
                executable: "/usr/bin/env",
                arguments: ["claude", "--version"]
            )

            guard result.exitCode == 0 else {
                return .unavailable(reason: "claude not found on PATH")
            }

            let trimmedOutput = result.standardOutput
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .split(separator: "\n")
                .first
                .map { String($0) } ?? ""
            let version = trimmedOutput.isEmpty ? "available" : trimmedOutput

            return .available(version: version)
        } catch {
            return .unavailable(reason: "claude not found on PATH")
        }
    }
}
