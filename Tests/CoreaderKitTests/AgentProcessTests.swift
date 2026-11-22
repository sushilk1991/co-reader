#if os(macOS)
import Foundation
import Testing
@testable import CoreaderKit

/// `/bin/sh` scripts stand in for agent CLIs.
enum FakeAgent {
    static func spec(_ script: String, stdin: Data? = nil, idle: Duration = .seconds(20), total: Duration? = nil) -> AgentProcessSpec {
        AgentProcessSpec(
            executable: URL(fileURLWithPath: "/bin/sh"), arguments: ["-c", script],
            environment: ["PATH": "/usr/bin:/bin"], stdin: stdin, idleTimeout: idle, totalTimeout: total
        )
    }

    static func isAlive(_ pid: pid_t) -> Bool { kill(pid, 0) == 0 }

    /// Polls, because a killed process takes a moment to disappear.
    static func waitUntilDead(_ pids: [pid_t], within seconds: Double = 5) async -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if !pids.contains(where: isAlive) { return true }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return false
    }
}

@Suite struct AgentProcessTests {
    func collect(_ spec: AgentProcessSpec) async throws -> [AgentProcessOutput] {
        var items: [AgentProcessOutput] = []
        for try await item in AgentProcess.launch(spec).output { items.append(item) }
        return items
    }

    @Test func streamsLinesAsTheyAreWritten() async throws {
        let process = AgentProcess.launch(FakeAgent.spec("echo first; sleep 1; echo second"))
        var arrivals: [(String, ContinuousClock.Instant)] = []
        for try await item in process.output {
            if case .stdout(let line) = item { arrivals.append((line, .now)) }
        }
        #expect(arrivals.map(\.0) == ["first", "second"])
        // Proof of streaming rather than buffering until exit.
        #expect(arrivals[1].1 - arrivals[0].1 > .milliseconds(500))
    }

    @Test func deliversAPartialLineAtEndOfFile() async throws {
        let items = try await collect(FakeAgent.spec("printf 'one\\ntwo'"))
        #expect(items == [.stdout("one"), .stdout("two"), .exited(0)])
    }

    @Test func handlesVeryLongLines() async throws {
        let items = try await collect(FakeAgent.spec("head -c 3000000 /dev/zero | tr '\\0' x; echo; echo end"))
        guard case .stdout(let long) = items.first else { Issue.record("no output"); return }
        #expect(long.utf8.count == 3_000_000)
        #expect(items.dropFirst() == [.stdout("end"), .exited(0)])
    }

    @Test func reportsStderrAndANonZeroExit() async throws {
        let items = try await collect(FakeAgent.spec("echo out; echo 'it broke' >&2; exit 3"))
        #expect(items.contains(.stdout("out")))
        #expect(items.contains(.stderr("it broke")))
        #expect(items.last == .exited(3))
    }

    @Test func feedsStdinAndClosesIt() async throws {
        // 2 MB is far more than a pipe buffer, so this deadlocks unless stdin is written concurrently.
        let input = Data(repeating: 0x61, count: 2_000_000)
        let items = try await collect(FakeAgent.spec("wc -c | tr -d ' '", stdin: input))
        #expect(items == [.stdout("2000000"), .exited(0)])
    }

    @Test func stdinIsClosedWhenNoneIsGiven() async throws {
        // `cat` would wait forever on an open, silent stdin.
        let items = try await collect(FakeAgent.spec("cat; echo done"))
        #expect(items == [.stdout("done"), .exited(0)])
    }

    @Test func aChildThatIgnoresItsStdinDoesNotCrashTheParent() async throws {
        let items = try await collect(FakeAgent.spec("exit 0", stdin: Data(repeating: 0x61, count: 1_000_000)))
        #expect(items == [.exited(0)])
    }

    @Test func runsInTheGivenDirectoryWithTheGivenEnvironment() async throws {
        var spec = FakeAgent.spec("pwd -P; echo $COREADER_TEST")
        spec.workingDirectory = URL(fileURLWithPath: "/usr/bin")
        spec.environment["COREADER_TEST"] = "yes"
        #expect(try await collect(spec) == [.stdout("/usr/bin"), .stdout("yes"), .exited(0)])
    }

    @Test func terminateKillsTheWholeProcessTree() async throws {
        let process = AgentProcess.launch(FakeAgent.spec("echo $$; sleep 60 & echo $!; wait"))
        var pids: [pid_t] = []
        for try await item in process.output {
            if case .stdout(let line) = item, let pid = pid_t(line) { pids.append(pid) }
            if pids.count == 2 { break }
        }
        #expect(pids.count == 2)
        #expect(pids.allSatisfy(FakeAgent.isAlive))
        process.terminate()
        #expect(await FakeAgent.waitUntilDead(pids))
    }

    @Test func cancellingTheReadingTaskKillsTheChild() async throws {
        let (pidStream, pidContinuation) = AsyncStream.makeStream(of: pid_t.self)
        let reader = Task {
            for try await item in AgentProcess.launch(FakeAgent.spec("echo $$; sleep 60 & echo $!; wait")).output {
                if case .stdout(let line) = item, let pid = pid_t(line) { pidContinuation.yield(pid) }
            }
        }
        var pids: [pid_t] = []
        for await pid in pidStream {
            pids.append(pid)
            if pids.count == 2 { break }
        }
        reader.cancel()
        #expect(await FakeAgent.waitUntilDead(pids))
    }

    @Test func aChildThatIgnoresSIGTERMIsKilled() async throws {
        let process = AgentProcess.launch(FakeAgent.spec("trap '' TERM; echo $$; while true; do sleep 1; done"))
        var pid: pid_t?
        for try await item in process.output {
            if case .stdout(let line) = item { pid = pid_t(line); break }
        }
        process.terminate()
        #expect(await FakeAgent.waitUntilDead([try #require(pid)]))
    }

    @Test func idleTimeoutFailsAndKills() async throws {
        let process = AgentProcess.launch(FakeAgent.spec("echo $$; sleep 60", idle: .milliseconds(400)))
        var pid: pid_t?
        await #expect(throws: AgentError.timedOut) {
            for try await item in process.output {
                if case .stdout(let line) = item { pid = pid_t(line) }
            }
        }
        #expect(await FakeAgent.waitUntilDead([try #require(pid)]))
    }

    @Test func steadyOutputKeepsASlowRunAlive() async throws {
        // Runs for 4x the idle timeout, but is never silent for that long.
        let items = try await collect(FakeAgent.spec(
            "for i in 1 2 3 4 5 6 7 8; do echo $i; sleep 0.2; done", idle: .milliseconds(400)
        ))
        #expect(items.last == .exited(0))
        #expect(items.count == 9)
    }

    @Test func totalTimeoutAppliesEvenWithSteadyOutput() async {
        await #expect(throws: AgentError.timedOut) {
            _ = try await collect(FakeAgent.spec("while true; do echo tick; sleep 0.1; done", total: .milliseconds(500)))
        }
    }

    @Test func aHelperHoldingThePipesOpenDoesNotBlockCompletion() async throws {
        let started = ContinuousClock.now
        let items = try await collect(FakeAgent.spec("(sleep 30 &); echo done"))
        #expect(items == [.stdout("done"), .exited(0)])
        #expect(ContinuousClock.now - started < .seconds(10))
    }

    @Test func expectedExitThatNeverComesEndsQuietly() async throws {
        let process = AgentProcess.launch(FakeAgent.spec("echo answer; sleep 60"))
        var lines: [AgentProcessOutput] = []
        for try await item in process.output {
            lines.append(item)
            process.expectExit(within: .milliseconds(300))
        }
        #expect(lines == [.stdout("answer")])
    }

    @Test func aMissingExecutableIsNotInstalled() async {
        var spec = FakeAgent.spec("true")
        spec.executable = URL(fileURLWithPath: "/nonexistent/claude")
        await #expect(throws: AgentError.notInstalled) { _ = try await collect(spec) }
    }

    @Test func captureCollectsBothStreams() async throws {
        let result = try await AgentProcess.capture(FakeAgent.spec("echo a; echo b >&2; exit 4"))
        #expect(result.stdout == "a\n")
        #expect(result.stderr == "b\n")
        #expect(result.exitCode == 4)
    }

    @Test func lineSplitterHandlesAnyChunking() {
        let text = "alpha\nbeta\r\n\ngamma ∂elta\nlast"
        let bytes = Array(text.utf8)
        for size in [1, 2, 3, 7, bytes.count] {
            var splitter = AgentLineSplitter()
            var lines: [String] = []
            for start in stride(from: 0, to: bytes.count, by: size) {
                lines += splitter.feed(Data(bytes[start..<min(start + size, bytes.count)]))
            }
            if let rest = splitter.finish() { lines.append(rest) }
            #expect(lines == ["alpha", "beta", "", "gamma ∂elta", "last"])
        }
    }
}
#endif
