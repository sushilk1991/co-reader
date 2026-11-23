import Foundation
import Testing
@testable import CoreaderKit

/// Feeds a captured transcript through a parser the way `AgentRun` does.
private func replay(
    _ parser: any AgentStreamParser, _ stdout: String, stderr: String = "", exitCode: Int32 = 0
) throws -> [AgentEvent] {
    var parser = parser
    var events: [AgentEvent] = []
    for line in stderr.split(separator: "\n") { events += try parser.consume(stderr: String(line)) }
    for line in stdout.split(separator: "\n") { events += try parser.consume(stdout: String(line)) }
    events += try parser.finish(exitCode: exitCode, stderr: stderr)
    return events
}

private func text(_ events: [AgentEvent]) -> String {
    events.reduce(into: "") { if case .textDelta(let chunk) = $1 { $0 += chunk } }
}

private func activities(_ events: [AgentEvent]) -> [String] {
    events.compactMap { if case .activity(let label) = $0 { label } else { nil } }
}

private func deltaCount(_ events: [AgentEvent]) -> Int {
    events.count { if case .textDelta = $0 { true } else { false } }
}

@Suite struct AgentParserTests {
    // MARK: Claude

    @Test func claudeStreamsTokenDeltasAndCompletes() throws {
        let events = try replay(ClaudeStreamParser(), AgentFixtures.claudeFirstTurn)
        let answer = "The secret code is MANGO-42 (and PINEAPPLE is noted)."
        #expect(events.first == .sessionStarted(id: "8eb72306-35a4-47b5-ae3c-a9b5f3b7dbc4"))
        #expect(activities(events) == ["Reading notes.md"])
        #expect(text(events) == answer)
        #expect(deltaCount(events) > 1)
        #expect(events.last == .completed(text: answer))
        #expect(events.count { if case .completed = $0 { true } else { false } } == 1)
    }

    @Test func claudeSeparatesMessagesAndReportsToolUse() throws {
        let events = try replay(ClaudeStreamParser(), AgentFixtures.claudeResumedTurnWithDenial)
        #expect(activities(events).contains("Reading hosts"))
        #expect(activities(events).contains("Thinking"))
        guard case .completed(let answer) = events.last else { Issue.record("no completed event"); return }
        #expect(answer.hasPrefix("The word was **PINEAPPLE**."))
        #expect(text(events) == answer)
    }

    @Test func claudeWithoutPartialMessagesEmitsWholeMessages() throws {
        let whole = AgentFixtures.claudeFirstTurn.split(separator: "\n")
            .filter { !$0.contains(#""type":"stream_event""#) }.joined(separator: "\n")
        let events = try replay(ClaudeStreamParser(), whole)
        #expect(text(events) == "The secret code is MANGO-42 (and PINEAPPLE is noted).")
        #expect(deltaCount(events) == 1)
    }

    @Test func claudeNotSignedIn() {
        #expect(throws: AgentError.signedOut(.claude)) {
            try replay(ClaudeStreamParser(), AgentFixtures.claudeNotSignedIn, exitCode: 1)
        }
    }

    @Test func claudeNotSignedInIsNotStreamedAsAnAnswer() throws {
        var parser = ClaudeStreamParser()
        var events: [AgentEvent] = []
        for line in AgentFixtures.claudeNotSignedIn.split(separator: "\n") {
            events += try parser.consume(stdout: String(line))
        }
        #expect(text(events).isEmpty)
    }

    @Test func claudeMissingSession() {
        let error = #expect(throws: AgentError.self) {
            try replay(
                ClaudeStreamParser(), AgentFixtures.claudeMissingSession,
                stderr: AgentFixtures.claudeMissingSessionStderr, exitCode: 1
            )
        }
        #expect(error?.isSessionMissing == true)
    }

    @Test func claudeCrashWithoutResultReportsStderr() {
        #expect(throws: AgentError.failed("boom")) {
            try replay(ClaudeStreamParser(), "", stderr: "boom", exitCode: 2)
        }
    }

    // MARK: Codex

    @Test func codexEmitsWholeMessagesAndCompletesWithTheLast() throws {
        let events = try replay(CodexStreamParser(), AgentFixtures.codexFirstTurn)
        #expect(events.first == .sessionStarted(id: "01a2049e-d7ba-7811-b283-0c3ce7e7fd02"))
        #expect(activities(events) == ["Reading notes.md"])
        #expect(text(events) == "I’ll read notes.md for the code. ZEBRA\n\nThe secret code is **MANGO-42**, and I’ll keep PINEAPPLE in mind. ZEBRA")
        #expect(events.last == .completed(text: "The secret code is **MANGO-42**, and I’ll keep PINEAPPLE in mind. ZEBRA"))
    }

    @Test func codexResumedTurnKeepsTheThreadID() throws {
        let events = try replay(CodexStreamParser(), AgentFixtures.codexResumedTurn)
        #expect(events.first == .sessionStarted(id: "01a2049e-d7ba-7811-b283-0c3ce7e7fd02"))
        #expect(events.last == .completed(text: "The word was **PINEAPPLE**. The read-only sandbox blocked creation of `blocked.md`. ZEBRA"))
    }

    @Test func codexWebSearchActivity() throws {
        let events = try replay(CodexStreamParser(), AgentFixtures.codexWebSearch)
        #expect(activities(events) == [
            "Searching the web",
            "Searching the web for “site:swift.org Swift latest stable release Swift 6 download”",
        ])
    }

    @Test func codexNotSignedInFailsOnTheFirstUnauthorizedRetry() throws {
        var parser = CodexStreamParser()
        let lines = AgentFixtures.codexNotSignedIn.split(separator: "\n").map(String.init)
        #expect(try parser.consume(stdout: lines[0]) == [.sessionStarted(id: "01a2049f-d6cc-7d53-a387-b4484f3080de")])
        #expect(try parser.consume(stdout: lines[1]).isEmpty)
        #expect(throws: AgentError.signedOut(.codex)) { try parser.consume(stdout: lines[2]) }
    }

    @Test func codexMissingSession() {
        let error = #expect(throws: AgentError.self) {
            try replay(CodexStreamParser(), "", stderr: AgentFixtures.codexMissingSessionStderr, exitCode: 1)
        }
        #expect(error?.isSessionMissing == true)
    }

    @Test func codexTurnFailedCarriesTheMessage() {
        let transcript = """
            {"type":"thread.started","thread_id":"t1"}
            {"type":"turn.failed","error":{"message":"You've hit your usage limit."}}
            """
        #expect(throws: AgentError.failed("You've hit your usage limit.")) {
            try replay(CodexStreamParser(), transcript, exitCode: 1)
        }
    }

    @Test func codexStderrNoiseIsReducedToTheErrorLine() {
        let stderr = """
            2026-11-22T18:58:34.068025Z ERROR codex_api::endpoint: failed to connect stage=Unknown
            Error: something specific went wrong
            """
        #expect(CodexStreamParser.meaningful(stderr) == "something specific went wrong")
    }

    // MARK: Antigravity

    @Test func antigravityStreamsDeltasAndCompletes() throws {
        let events = try replay(AntigravityStreamParser(), AgentFixtures.antigravityFirstTurn)
        #expect(events.first == .sessionStarted(id: "9da2820d-d036-43b6-92a7-bb705e2bbb42"))
        #expect(activities(events) == ["Reading notes.md"])
        #expect(deltaCount(events) > 1)
        guard case .completed(let answer) = events.last else { Issue.record("no completed event"); return }
        #expect(answer.contains("MANGO-42"))
        #expect(text(events).trimmingCharacters(in: .whitespacesAndNewlines) == answer)
    }

    @Test func antigravityAcceptsTheExpectedConversation() throws {
        let parser = AntigravityStreamParser(expectedConversation: "9da2820d-d036-43b6-92a7-bb705e2bbb42")
        #expect(try replay(parser, AgentFixtures.antigravityFirstTurn).isEmpty == false)
    }

    @Test func antigravityAutoDeniedActionIsAnErrorNotAnEmptyAnswer() {
        let error = #expect(throws: AgentError.self) {
            try replay(AntigravityStreamParser(), AgentFixtures.antigravityDeniedAction)
        }
        guard case .failed(let message) = error else { Issue.record("expected .failed"); return }
        #expect(message.contains("Edit"))
    }

    @Test func antigravityCarriesOnAfterADenyRule() throws {
        let events = try replay(AntigravityStreamParser(), AgentFixtures.antigravityRecoveredFromDenyRule)
        #expect(activities(events) == ["Editing deny.md"])
        guard case .completed(let answer) = events.last else { Issue.record("no completed event"); return }
        #expect(answer.hasPrefix("It did not work."))
    }

    @Test func antigravityNotSignedIn() {
        #expect(throws: AgentError.signedOut(.antigravity)) {
            try replay(AntigravityStreamParser(), "", stderr: AgentFixtures.antigravityNotSignedInStderr)
        }
        #expect(throws: AgentError.signedOut(.antigravity)) {
            try replay(AntigravityStreamParser(), AgentFixtures.antigravityNotSignedIn, exitCode: 1)
        }
    }

    @Test func antigravitySilentlyStartingANewConversationIsDetected() {
        let stale = "00000000-0000-4000-8000-000000000000"
        let fromInit = #expect(throws: AgentError.self) {
            try replay(AntigravityStreamParser(expectedConversation: stale), AgentFixtures.antigravityMissingConversation)
        }
        #expect(fromInit?.isSessionMissing == true)
        let fromWarning = #expect(throws: AgentError.self) {
            try replay(
                AntigravityStreamParser(expectedConversation: stale), "",
                stderr: AgentFixtures.antigravityMissingConversationStderr
            )
        }
        #expect(fromWarning?.isSessionMissing == true)
    }

    // MARK: Shared

    @Test func parsersIgnoreLinesThatAreNotJSON() throws {
        let noise = "warning: something\n{not json\n\n{\"unrelated\":true}"
        #expect(try replay(ClaudeStreamParser(), noise) == [.completed(text: "")])
        #expect(try replay(CodexStreamParser(), noise) == [.completed(text: "")])
        #expect(try replay(AntigravityStreamParser(), noise) == [.completed(text: "")])
    }

    @Test func commandsAreDescribedForReaders() {
        #expect(AgentActivity.command("/bin/zsh -lc 'cat notes.md'") == "Reading notes.md")
        #expect(AgentActivity.command("/bin/zsh -lc \"sed -n '1,40p' text/012-attention.md\"") == "Reading 012-attention.md")
        #expect(AgentActivity.command("/bin/zsh -lc 'rg -n attention .'") == "Searching the book files")
        #expect(AgentActivity.command("python3 script.py") == "Running python3 script.py")
    }

    @Test func errorsAreUserPresentable() {
        #expect(AgentError.signedOut(.codex).errorDescription?.contains("Codex is not signed in") == true)
        #expect(AgentError.classify("", kind: .claude) == .failed("Claude Code stopped without an answer."))
        #expect(AgentError.classify(String(repeating: "x", count: 5_000), kind: .claude).errorDescription!.count < 700)
        #expect(AgentError.timedOut.errorDescription != nil)
    }
}
