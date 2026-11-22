#if os(macOS)
import Foundation
import Testing
@testable import CoreaderKit

/// An adapter whose "CLI" is a shell script speaking a small line protocol:
/// `session <id>`, `delta <text>`, `note <activity>`, `done <answer>`, `gone`.
private struct ScriptAdapter: AgentAdapter {
    let kind = AgentKind.claude
    /// Receives the turn, returns the script to run.
    var script: @Sendable (AgentTurn) -> String

    func invocation(for turn: AgentTurn) throws -> AgentInvocation {
        AgentInvocation(
            arguments: ["-c", script(turn)], stdin: Data(turn.prompt.utf8),
            workingDirectory: turn.config.workingDirectory
        )
    }

    func makeParser(for turn: AgentTurn) -> any AgentStreamParser { ScriptParser() }
}

private struct ScriptParser: AgentStreamParser {
    var done = false

    mutating func consume(stdout line: String) throws -> [AgentEvent] {
        let parts = line.split(separator: " ", maxSplits: 1).map(String.init)
        guard let word = parts.first else { return [] }
        let rest = parts.count > 1 ? parts[1] : ""
        switch word {
        case "session": return [.sessionStarted(id: rest)]
        case "delta": return [.textDelta(rest)]
        case "note": return [.activity(rest)]
        case "done": done = true; return [.completed(text: rest)]
        case "gone": throw AgentError.sessionMissing
        default: return []
        }
    }

    mutating func consume(stderr line: String) throws -> [AgentEvent] { [] }

    mutating func finish(exitCode: Int32, stderr: String) throws -> [AgentEvent] {
        if done { return [] }
        throw AgentError.classify(stderr, kind: .claude)
    }
}

@Suite struct AgentSessionTests {
    let shell = DetectedAgent(kind: .claude, executable: URL(fileURLWithPath: "/bin/sh"))
    let config = AgentSessionConfig(workingDirectory: URL(fileURLWithPath: "/tmp"), idleTimeout: .seconds(20))

    private func session(resuming id: String? = nil, _ script: @escaping @Sendable (AgentTurn) -> String) -> AgentSession {
        AgentSession(agent: shell, config: config, sessionID: id, adapter: ScriptAdapter(script: script))
    }

    private func collect(_ stream: AsyncThrowingStream<AgentEvent, Error>) async throws -> [AgentEvent] {
        var events: [AgentEvent] = []
        for try await event in stream { events.append(event) }
        return events
    }

    @Test func firstTurnCreatesTheSessionAndLaterTurnsResumeIt() async throws {
        let session = session { turn in
            if let id = turn.resumeID { return "echo 'session \(id)'; echo \"done resumed \(id): $(cat)\"" }
            return "echo 'session s-1'; echo 'note Reading notes.md'; echo 'delta Hel'; echo 'delta lo'; echo 'done Hello'"
        }
        #expect(session.sessionID == nil)
        let first = try await collect(session.send("one"))
        #expect(first == [
            .sessionStarted(id: "s-1"), .activity("Reading notes.md"), .textDelta("Hel"), .textDelta("lo"),
            .completed(text: "Hello"),
        ])
        #expect(session.sessionID == "s-1")
        let second = try await collect(session.send("two", attachments: []))
        #expect(second.last == .completed(text: "resumed s-1: two"))
    }

    @Test func aStoredSessionIDIsResumedByANewObject() async throws {
        let session = session(resuming: "stored-9") { turn in "echo 'done \(turn.resumeID ?? "none")'" }
        #expect(session.sessionID == "stored-9")
        #expect(try await collect(session.send("hi")) == [.completed(text: "stored-9")])
    }

    @Test func turnsSentTogetherRunInOrder() async throws {
        let session = session { turn in
            turn.resumeID == nil
                ? "sleep 0.5; echo 'session s-1'; echo 'done first'"
                : "echo 'done second after \(turn.resumeID!)'"
        }
        let first = session.send("a")
        let second = session.send("b")
        async let secondEvents = collect(second)
        #expect(try await collect(first).last == .completed(text: "first"))
        #expect(try await secondEvents.last == .completed(text: "second after s-1"))
    }

    @Test func theStreamEndsAtTheAnswerWithoutWaitingForTheProcess() async throws {
        let session = session { _ in "echo 'done quick'; sleep 3" }
        let started = ContinuousClock.now
        #expect(try await collect(session.send("hi")) == [.completed(text: "quick")])
        #expect(ContinuousClock.now - started < .seconds(2))
    }

    @Test func outputAfterTheAnswerIsIgnored() async throws {
        let session = session { _ in "echo 'done answer'; echo 'delta late'; echo 'done again'; echo oops >&2; exit 1" }
        #expect(try await collect(session.send("hi")) == [.completed(text: "answer")])
    }

    @Test func cancelStopsTheTurnAndKillsTheProcessTree() async throws {
        let session = session { _ in "echo \"note $$\"; sleep 60 & echo \"note $!\"; wait" }
        var pids: [pid_t] = []
        let error = await #expect(throws: AgentError.self) {
            for try await event in session.send("hi") {
                if case .activity(let text) = event, let pid = pid_t(text) { pids.append(pid) }
                if pids.count == 2 { session.cancel() }
            }
        }
        #expect(error == .cancelled)
        #expect(pids.count == 2)
        #expect(await FakeAgent.waitUntilDead(pids))
    }

    @Test func droppingTheStreamCancelsTheTurn() async throws {
        let session = session { _ in "echo \"note $$\"; sleep 60" }
        var pid: pid_t?
        for try await event in session.send("hi") {
            if case .activity(let text) = event { pid = pid_t(text); break }
        }
        #expect(await FakeAgent.waitUntilDead([try #require(pid)]))
    }

    @Test func theSessionIsUsableAfterACancelledTurn() async throws {
        let session = session { turn in
            turn.prompt == "slow" ? "echo 'session s-1'; echo 'note started'; sleep 60" : "echo 'done ok \(turn.resumeID ?? "new")'"
        }
        await #expect(throws: AgentError.cancelled) {
            for try await event in session.send("slow") where event == .activity("started") { session.cancel() }
        }
        // s-1 was announced but, as far as the session knows, may not have been
        // saved; this fake still has it, so the turn resumes it.
        #expect(try await collect(session.send("fast")).last == .completed(text: "ok s-1"))
    }

    @Test func aFailingCLISurfacesItsStderr() async {
        let session = session { _ in "echo 'delta partial'; echo 'quota exceeded' >&2; exit 1" }
        await #expect(throws: AgentError.failed("quota exceeded")) { _ = try await collect(session.send("hi")) }
    }

    @Test func notSignedInIsRecognised() async {
        let session = session { _ in "echo 'Not logged in · Please run /login' >&2; exit 1" }
        await #expect(throws: AgentError.signedOut(.claude)) { _ = try await collect(session.send("hi")) }
    }

    @Test func aStoredSessionThatIsGoneIsAClearError() async {
        let session = session(resuming: "stale") { _ in "echo gone" }
        let error = await #expect(throws: AgentError.self) { _ = try await collect(session.send("hi")) }
        #expect(error?.isSessionMissing == true)
        #expect(error?.errorDescription?.contains("Start a new conversation") == true)
    }

    @Test func aSessionThatNeverSavedAnythingStartsOver() async throws {
        // Turn 1 is cancelled right after the CLI announces its id; the CLI then
        // has no such session, and nothing is lost by beginning a new one.
        let session = session { turn in
            switch (turn.prompt, turn.resumeID) {
            case ("slow", _): "echo 'session never-saved'; echo 'note started'; sleep 60"
            case (_, "never-saved"?): "echo gone"
            default: "echo 'session fresh'; echo 'done started over'"
            }
        }
        await #expect(throws: AgentError.cancelled) {
            for try await event in session.send("slow") where event == .activity("started") { session.cancel() }
        }
        #expect(session.sessionID == "never-saved")
        #expect(try await collect(session.send("again")).last == .completed(text: "started over"))
        #expect(session.sessionID == "fresh")
    }

    @Test func aSilentCLITimesOut() async {
        var quiet = config
        quiet.idleTimeout = .milliseconds(400)
        let session = AgentSession(
            agent: shell, config: quiet, sessionID: nil, adapter: ScriptAdapter { _ in "echo 'note working'; sleep 60" }
        )
        await #expect(throws: AgentError.timedOut) { _ = try await collect(session.send("hi")) }
    }

    @Test func aMissingExecutableIsNotInstalled() async {
        let missing = DetectedAgent(kind: .codex, executable: URL(fileURLWithPath: "/nonexistent/codex"))
        let session = AgentSession(agent: missing, config: config)
        await #expect(throws: AgentError.notInstalled) { _ = try await collect(session.send("hi")) }
    }

    // MARK: One-shot

    @Test func oneShotReturnsTheAnswer() async throws {
        let oneShot = AgentOneShot(agent: shell, adapter: ScriptAdapter { turn in
            "echo 'delta x'; echo \"done \(turn.mode == .oneShot ? "oneshot" : "conversation"): $(cat)\""
        })
        #expect(try await oneShot.complete("why?", workingDirectory: nil, timeout: .seconds(20)) == "oneshot: why?")
    }

    @Test func oneShotTimesOut() async {
        let oneShot = AgentOneShot(agent: shell, adapter: ScriptAdapter { _ in "while true; do echo 'delta x'; sleep 0.1; done" })
        await #expect(throws: AgentError.timedOut) {
            _ = try await oneShot.complete("why?", workingDirectory: nil, timeout: .milliseconds(500))
        }
    }

    @Test func oneShotCancellationKillsTheCLI() async throws {
        let pidFile = FileManager.default.temporaryDirectory.appendingPathComponent("coreader-pid-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: pidFile) }
        let oneShot = AgentOneShot(agent: shell, adapter: ScriptAdapter { _ in "echo $$ > '\(pidFile.path)'; sleep 60" })
        let task = Task { try await oneShot.complete("why?", workingDirectory: nil, timeout: .seconds(30)) }
        var pid: pid_t?
        for _ in 0..<100 where pid == nil {
            try await Task.sleep(for: .milliseconds(50))
            pid = (try? String(contentsOf: pidFile, encoding: .utf8)).flatMap { pid_t($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
        }
        task.cancel()
        _ = await task.result
        #expect(await FakeAgent.waitUntilDead([try #require(pid)]))
    }
}
#endif
