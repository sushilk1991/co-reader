import Foundation
import Testing
@testable import CoReaderApp

struct ClaudeCodeClientTests {
    /// The prompt goes over stdin; argv has a length limit and shows up in `ps`.
    @Test
    func generatePassesPromptOnStandardInputNotArgv() async throws {
        let runner = RecordingCommandRunner(
            result: ShellCommandResult(standardOutput: "  answer \n", standardError: "", exitCode: 0)
        )
        let client = ClaudeCodeClient(commandRunner: runner)
        let prompt = "Summarize chapter 4."

        let answer = try await client.generate(prompt: prompt)

        let command = try #require(await runner.lastCommand)
        #expect(answer == "answer")
        #expect(command.standardInput == prompt)
        #expect(!command.arguments.contains(prompt))
        #expect(command.arguments == ["claude", "-p", "--output-format", "text", "--no-session-persistence"])
        #expect(command.timeout > .zero)
    }

    @Test
    func generateSurfacesStandardErrorOnFailure() async {
        let runner = RecordingCommandRunner(
            result: ShellCommandResult(standardOutput: "", standardError: "not logged in", exitCode: 1)
        )
        let client = ClaudeCodeClient(commandRunner: runner)

        do {
            _ = try await client.generate(prompt: "hello")
            Issue.record("Expected failure.")
        } catch {
            #expect(error.localizedDescription == "not logged in")
        }
    }
}

struct ClaudeCLIProbeTests {
    /// A hung `claude --version` must report the timeout, not "not found".
    @Test
    func probeReportsTimeoutReason() async throws {
        let runner = ThrowingCommandRunner(
            error: ShellCommandError.timedOut(executable: "/bin/zsh", timeout: .seconds(15))
        )
        let probe = ClaudeCLIProbe(commandRunner: runner)

        let result = try await probe.probe()

        guard case let .unavailable(reason) = result else {
            Issue.record("Expected unavailable, got \(result)")
            return
        }
        #expect(reason.contains("did not finish"))
    }
}

actor RecordingCommandRunner: ShellCommandRunning {
    private(set) var lastCommand: ShellCommand?
    private let result: ShellCommandResult

    init(result: ShellCommandResult) {
        self.result = result
    }

    func run(_ command: ShellCommand) async throws -> ShellCommandResult {
        lastCommand = command
        return result
    }
}

struct ThrowingCommandRunner: ShellCommandRunning {
    let error: any Error

    func run(_ command: ShellCommand) async throws -> ShellCommandResult {
        throw error
    }
}
