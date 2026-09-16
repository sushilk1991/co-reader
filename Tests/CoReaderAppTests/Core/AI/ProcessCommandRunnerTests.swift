import Foundation
import Testing
@testable import CoReaderApp

struct ProcessCommandRunnerTests {
    private static let quickTimeout: Duration = .milliseconds(300)
    private static let generousTimeout: Duration = .seconds(10)

    /// A hung child must fail with a timeout instead of pinning a thread forever.
    @Test
    func runFailsFastWhenProcessOutlivesTimeout() async throws {
        let runner = ProcessCommandRunner()
        let command = ShellCommand(
            executable: "/bin/sleep",
            arguments: ["30"],
            standardInput: nil,
            timeout: Self.quickTimeout
        )
        let clock = ContinuousClock()
        let start = clock.now

        await #expect(throws: ShellCommandError.self) {
            _ = try await runner.run(command)
        }

        #expect(clock.now - start < .seconds(5))
    }

    @Test
    func timeoutErrorNamesTheExecutableAndDuration() async {
        let runner = ProcessCommandRunner()
        let command = ShellCommand(
            executable: "/bin/sleep",
            arguments: ["30"],
            standardInput: nil,
            timeout: Self.quickTimeout
        )

        do {
            _ = try await runner.run(command)
            Issue.record("Expected a timeout error.")
        } catch let error as ShellCommandError {
            #expect(error.localizedDescription.contains("sleep"))
            #expect(error.localizedDescription.contains("did not finish"))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    /// Prompts larger than the pipe buffer (64 KiB) must arrive intact on stdin.
    @Test
    func runFeedsStandardInputToProcess() async throws {
        let runner = ProcessCommandRunner()
        let payload = String(repeating: "line of prompt text that exceeds the pipe buffer\n", count: 5_000)
        let command = ShellCommand(
            executable: "/bin/cat",
            arguments: [],
            standardInput: payload,
            timeout: Self.generousTimeout
        )

        let result = try await runner.run(command)

        #expect(result.exitCode == 0)
        #expect(result.standardOutput == payload)
    }

    @Test
    func runCapturesStandardErrorAndExitCode() async throws {
        let runner = ProcessCommandRunner()
        let command = ShellCommand(
            executable: "/bin/sh",
            arguments: ["-c", "echo out; echo oops >&2; exit 3"],
            standardInput: nil,
            timeout: Self.generousTimeout
        )

        let result = try await runner.run(command)

        #expect(result.exitCode == 3)
        #expect(result.standardOutput == "out\n")
        #expect(result.standardError == "oops\n")
    }
}
