import Foundation

struct ClaudeCodeClient: ClaudeGenerating {
    let commandRunner: ShellCommandRunning

    init(commandRunner: ShellCommandRunning = ProcessCommandRunner()) {
        self.commandRunner = commandRunner
    }

    /// Upper bound for one generation; the CLI streams nothing back until it is done.
    static let generationTimeout: Duration = .seconds(300)

    func generate(prompt: String) async throws -> String {
        // The prompt travels over stdin: argv is size-limited and visible in `ps`.
        let result = try await commandRunner.run(
            ShellCommand(
                executable: "/usr/bin/env",
                arguments: [
                    "claude",
                    "-p",
                    "--output-format",
                    "text",
                    "--no-session-persistence"
                ],
                standardInput: prompt,
                timeout: Self.generationTimeout
            )
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
