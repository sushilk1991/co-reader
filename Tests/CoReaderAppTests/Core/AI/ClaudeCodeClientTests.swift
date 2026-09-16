import Foundation
import Testing
@testable import CoReaderApp

struct ClaudeCodeClientTests {
    /// A GUI PATH must not disagree with the successful login-shell availability probe:
    /// both the version check and generation spawn the binary the login shell located.
    @Test
    func generationUsesProbeFallback() async throws {
        let runner = LoginShellClaudeRunner()
        let locator = ClaudeCLILocator(commandRunner: runner, commonPaths: [])
        let availability = try await ClaudeCLIProbe(locator: locator, commandRunner: runner).probe()
        #expect(availability == .available(version: "test-version"))

        let answer = try await ClaudeCodeClient(locator: locator, commandRunner: runner).generate(prompt: "Explain this page")

        #expect(answer == "answer")
        let generation = try #require(await runner.generation)
        #expect(generation.executable == LoginShellClaudeRunner.claudePath)
        #expect(generation.standardInput == "Explain this page")
    }

    /// Whatever `.zprofile` prints runs before any command in a login shell; it must never
    /// reach the answer, so the answer comes from the located binary, not the shell.
    @Test
    func loginShellOutputStaysOutOfAnswer() async throws {
        let runner = LoginShellClaudeRunner()
        let locator = ClaudeCLILocator(commandRunner: runner, commonPaths: [])

        let answer = try await ClaudeCodeClient(locator: locator, commandRunner: runner).generate(prompt: "Explain this page")

        #expect(answer == "answer")
        #expect(!answer.contains(LoginShellClaudeRunner.dotfileBanner))
        let generation = try #require(await runner.generation)
        #expect(generation.executable != "/bin/zsh")
    }

    /// Auto-summary generates once per page visited; the login shell is paid once per session, not per page.
    @Test
    func loginShellResolutionRunsOncePerSession() async throws {
        let runner = LoginShellClaudeRunner()
        let locator = ClaudeCLILocator(commandRunner: runner, commonPaths: [])
        let client = ClaudeCodeClient(locator: locator, commandRunner: runner)

        _ = try await ClaudeCLIProbe(locator: locator, commandRunner: runner).probe()
        _ = try await client.generate(prompt: "Page 1")
        _ = try await client.generate(prompt: "Page 2")

        #expect(await runner.loginShellRuns == 1)
    }

    /// Missing installations must fail clearly before any generation command runs.
    @Test
    func missingClaudeReportsReason() async throws {
        let runner = LoginShellClaudeRunner(availability: .missing)
        let locator = ClaudeCLILocator(commandRunner: runner, commonPaths: [])
        let probe = ClaudeCLIProbe(locator: locator, commandRunner: runner)
        #expect(try await probe.probe() == .unavailable(reason: "claude not found on PATH"))

        do {
            _ = try await ClaudeCodeClient(locator: locator, commandRunner: runner).generate(prompt: "hello")
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
        let client = ClaudeCodeClient(locator: ClaudeCLILocator(commandRunner: runner, commonPaths: []), commandRunner: runner)
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
        let client = ClaudeCodeClient(locator: ClaudeCLILocator(commandRunner: runner, commonPaths: []), commandRunner: runner)

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
        let probe = ClaudeCLIProbe(locator: ClaudeCLILocator(commandRunner: runner, commonPaths: []), commandRunner: runner)

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
        // Location and version checks succeed; the configured result belongs to generation.
        if command.executable == "/bin/zsh" {
            return ShellCommandResult(standardOutput: "/usr/local/bin/claude\n", standardError: "", exitCode: EXIT_SUCCESS)
        }

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

/// Model a CLI reachable only through a login shell whose dotfiles print a banner,
/// independently of the test host's PATH.
private actor LoginShellClaudeRunner: ShellCommandRunning {
    enum Availability {
        case installed
        case missing
    }

    static let claudePath = "/Users/reader/.local/bin/claude"
    static let dotfileBanner = "Welcome back, printed by .zprofile"
    private static let commandNotFoundExit: Int32 = 127
    private let availability: Availability
    private(set) var generation: ShellCommand?
    private(set) var loginShellRuns = 0

    init(availability: Availability = .installed) {
        self.availability = availability
    }

    func run(_ command: ShellCommand) async throws -> ShellCommandResult {
        if command.executable == "/bin/zsh" {
            return runLoginShell(command)
        }

        guard availability == .installed, command.executable == Self.claudePath else {
            return ShellCommandResult(standardOutput: "", standardError: "claude: No such file", exitCode: Self.commandNotFoundExit)
        }

        guard command.standardInput != nil else {
            return ShellCommandResult(standardOutput: "test-version\n", standardError: "", exitCode: EXIT_SUCCESS)
        }

        generation = command
        return ShellCommandResult(standardOutput: "answer\n", standardError: "", exitCode: EXIT_SUCCESS)
    }

    /// Dotfiles print first; the shell then prints whatever the requested command prints.
    private func runLoginShell(_ command: ShellCommand) -> ShellCommandResult {
        loginShellRuns += 1
        guard availability == .installed else {
            return ShellCommandResult(standardOutput: Self.dotfileBanner + "\n", standardError: "claude not found", exitCode: Self.commandNotFoundExit)
        }

        let commandOutput: String
        if command.arguments.last == "command -v claude" {
            commandOutput = Self.claudePath
        } else if command.standardInput != nil {
            generation = command
            commandOutput = "answer"
        } else {
            commandOutput = "test-version"
        }

        return ShellCommandResult(
            standardOutput: Self.dotfileBanner + "\n" + commandOutput + "\n",
            standardError: "",
            exitCode: EXIT_SUCCESS
        )
    }
}
