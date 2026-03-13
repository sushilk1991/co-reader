import Foundation

struct ClaudeCodeClient: ClaudeGenerating {
    let commandRunner: ShellCommandRunning

    init(commandRunner: ShellCommandRunning = ProcessCommandRunner()) {
        self.commandRunner = commandRunner
    }

    func generate(prompt: String) async throws -> String {
        let result = try await commandRunner.run(
            executable: "/usr/bin/env",
            arguments: [
                "claude",
                "-p",
                prompt,
                "--output-format",
                "text",
                "--no-session-persistence"
            ]
        )

        guard result.exitCode == 0 else {
            throw NSError(
                domain: "CoReader.ClaudeCodeClient",
                code: Int(result.exitCode),
                userInfo: [
                    NSLocalizedDescriptionKey: result.standardError.isEmpty ? "Claude CLI request failed." : result.standardError
                ]
            )
        }

        return result.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
