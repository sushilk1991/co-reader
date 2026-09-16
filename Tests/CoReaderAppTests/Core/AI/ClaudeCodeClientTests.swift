import Foundation
import Testing
@testable import CoReaderApp

struct ClaudeCodeClientTests {
    /// A GUI PATH must not disagree with the successful login-shell availability probe.
    @Test
    func generationUsesProbeFallback() async throws {
        let runner = LoginShellClaudeRunner()
        let availability = try await ClaudeCLIProbe(commandRunner: runner).probe()
        #expect(availability == .available(version: "test-version"))

        let answer = try await ClaudeCodeClient(commandRunner: runner).generate(prompt: "Explain this page")

        #expect(answer == "answer from login shell")
        let generation = try #require(await runner.generation)
        #expect(generation.executable == "/bin/zsh")
        #expect(generation.standardInput == "Explain this page")
    }

    /// Missing installations must fail clearly before any generation command runs.
    @Test
    func missingClaudeReportsReason() async throws {
        let runner = LoginShellClaudeRunner(availability: .missing)
        let probe = ClaudeCLIProbe(commandRunner: runner)
        #expect(try await probe.probe() == .unavailable(reason: "claude not found on PATH"))

        do {
            _ = try await ClaudeCodeClient(commandRunner: runner).generate(prompt: "hello")
            Issue.record("Expected a missing CLI error.")
        } catch {
            #expect(error.localizedDescription == "claude not found on PATH")
        }
        #expect(await runner.generation == nil)
    }

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
        #expect(Array(command.arguments.suffix(4)) == ["-p", "--output-format", "text", "--no-session-persistence"])
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
        // Version checks succeed; the configured result belongs to generation.
        if command.standardInput == nil {
            return ShellCommandResult(standardOutput: "test-version", standardError: "", exitCode: EXIT_SUCCESS)
        }

        return result
    }
}

struct ThrowingCommandRunner: ShellCommandRunning {
    let error: any Error

    func run(_ command: ShellCommand) async throws -> ShellCommandResult {
        throw error
    }
}

/// Model a CLI available only in a login shell, independently of the test host's PATH.
private actor LoginShellClaudeRunner: ShellCommandRunning {
    enum Availability {
        case installed
        case missing
    }

    private static let commandNotFoundExit: Int32 = 127
    private let availability: Availability
    private(set) var generation: ShellCommand?

    init(availability: Availability = .installed) {
        self.availability = availability
    }

    func run(_ command: ShellCommand) async throws -> ShellCommandResult {
        guard availability == .installed else {
            return ShellCommandResult(standardOutput: "", standardError: "not found", exitCode: Self.commandNotFoundExit)
        }

        if command.standardInput != nil {
            generation = command
            guard command.executable == "/bin/zsh" else {
                return ShellCommandResult(standardOutput: "", standardError: "claude: No such file", exitCode: Self.commandNotFoundExit)
            }

            return ShellCommandResult(standardOutput: "answer from login shell", standardError: "", exitCode: EXIT_SUCCESS)
        }

        guard command.executable == "/bin/zsh" else {
            return ShellCommandResult(standardOutput: "", standardError: "not found", exitCode: Self.commandNotFoundExit)
        }

        return ShellCommandResult(standardOutput: "test-version", standardError: "", exitCode: EXIT_SUCCESS)
    }
}
