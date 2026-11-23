import Foundation
import Synchronization

/// One conversation with an agent CLI. Each turn is a separate run of the CLI;
/// continuity comes from the CLI's own session, resumed by id.
///
/// Claude Code and Codex look a session up relative to the working directory,
/// so resume with the same `config.workingDirectory` the session was created in.
public final class AgentSession: Sendable {
    public let agent: DetectedAgent
    public let config: AgentSessionConfig

    private struct State {
        var sessionID: String?
        /// The id came from the app's storage, so a failed resume is reported
        /// rather than papered over with a new conversation.
        var resumedFromStorage = false
        var hasCompletedTurn = false
        var tail: Task<Void, Never>?
        var active: [UUID: Task<Void, Never>] = [:]
    }

    private let state: Mutex<State>
    private let adapter: any AgentAdapter

    public convenience init(agent: DetectedAgent, config: AgentSessionConfig) {
        self.init(agent: agent, config: config, sessionID: nil, adapter: agent.kind.adapter)
    }

    public convenience init(agent: DetectedAgent, config: AgentSessionConfig, resuming sessionID: String) {
        self.init(agent: agent, config: config, sessionID: sessionID, adapter: agent.kind.adapter)
    }

    init(agent: DetectedAgent, config: AgentSessionConfig, sessionID: String?, adapter: any AgentAdapter) {
        self.agent = agent
        self.config = config
        self.adapter = adapter
        state = Mutex(State(sessionID: sessionID, resumedFromStorage: sessionID != nil))
    }

    /// The CLI's native session id, known shortly after the first turn starts.
    /// Persist it to continue the conversation later with `init(…resuming:)`.
    public var sessionID: String? { state.withLock { $0.sessionID } }

    /// Sends one user turn. `attachments` are image files.
    ///
    /// Events arrive as `sessionStarted`, then any mix of `textDelta` and
    /// `activity`, then `completed`. The stream throws `AgentError`. Turns sent
    /// while another is running wait for it; dropping the stream cancels the turn.
    public func send(_ prompt: String, attachments: [URL] = []) -> AsyncThrowingStream<AgentEvent, Error> {
        let (stream, continuation) = AsyncThrowingStream.makeStream(of: AgentEvent.self, throwing: Error.self)
        let id = UUID()
        let task = state.withLock { state in
            let previous = state.tail
            let task = Task { [self] in
                await previous?.value
                await runTurn(prompt: prompt, attachments: attachments, continuation: continuation)
                self.state.withLock { $0.active[id] = nil }
            }
            state.tail = task
            state.active[id] = task
            return task
        }
        continuation.onTermination = { reason in
            // `.finished` is the turn ending by itself; the CLI is then left to exit cleanly.
            if case .cancelled = reason { task.cancel() }
        }
        return stream
    }

    /// Stops the turn in flight (and any waiting behind it) and kills the CLI's
    /// process tree. Their streams throw `AgentError.cancelled`.
    public func cancel() {
        let tasks = state.withLock { Array($0.active.values) }
        tasks.forEach { $0.cancel() }
    }

    // MARK: - Turns

    private func runTurn(
        prompt: String, attachments: [URL], continuation: AsyncThrowingStream<AgentEvent, Error>.Continuation
    ) async {
        do {
            var retried = false
            while true {
                if Task.isCancelled { throw AgentError.cancelled }
                let turn = AgentTurn(
                    prompt: prompt, attachments: attachments, config: config, resumeID: sessionID
                )
                do {
                    try await execute(turn, continuation: continuation)
                    break
                } catch let error as AgentError where error.isSessionMissing && !retried && canStartOver() {
                    // The first turn was stopped after the CLI announced an id
                    // but before it saved anything. Nothing is lost by starting over.
                    retried = true
                    state.withLock { $0.sessionID = nil }
                }
            }
            continuation.finish()
        } catch {
            continuation.finish(throwing: Task.isCancelled ? AgentError.cancelled : error)
        }
    }

    private func canStartOver() -> Bool {
        state.withLock { !$0.resumedFromStorage && !$0.hasCompletedTurn }
    }

    private func execute(
        _ turn: AgentTurn, continuation: AsyncThrowingStream<AgentEvent, Error>.Continuation
    ) async throws {
        #if os(macOS)
        let events = AgentRun.events(adapter: adapter, executable: agent.executable, turn: turn) { [weak self] id in
            self?.state.withLock { $0.sessionID = id }
        }
        var completed = false
        for try await event in events {
            if case .completed = event {
                completed = true
                state.withLock { $0.hasCompletedTurn = true }
                continuation.yield(event)
                // The answer is in; do not make the caller wait for the CLI to exit.
                continuation.finish()
            } else {
                continuation.yield(event)
            }
        }
        if !completed {
            throw Task.isCancelled ? AgentError.cancelled : AgentError.failed("\(agent.kind.displayName) stopped without an answer.")
        }
        #else
        throw AgentError.notInstalled
        #endif
    }
}

#if os(macOS)

/// Runs one invocation and translates its output into events.
enum AgentRun {
    /// How long a CLI gets to save its session and exit after it has answered.
    static let exitGrace = Duration.seconds(15)

    /// The stream ends after the process has exited (or was killed), which for
    /// a successful turn is some time after `.completed` was yielded.
    static func events(
        adapter: any AgentAdapter,
        executable: URL,
        turn: AgentTurn,
        totalTimeout: Duration? = nil,
        onSessionID: @escaping @Sendable (String) -> Void = { _ in }
    ) -> AsyncThrowingStream<AgentEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let invocation = try adapter.invocation(for: turn)
                    var parser = adapter.makeParser(for: turn)
                    let process = AgentProcess.launch(AgentProcessSpec(
                        executable: executable,
                        arguments: invocation.arguments,
                        environment: AgentEnvironment.environment(for: executable),
                        workingDirectory: invocation.workingDirectory,
                        stdin: invocation.stdin,
                        idleTimeout: turn.config.idleTimeout,
                        totalTimeout: totalTimeout
                    ))
                    var completed = false
                    var stderrTail = ""
                    do {
                        for try await output in process.output {
                            let events: [AgentEvent]
                            switch output {
                            case .stdout(let line):
                                events = try parser.consume(stdout: line)
                            case .stderr(let line):
                                stderrTail = String((stderrTail + line + "\n").suffix(8_000))
                                events = try parser.consume(stderr: line)
                            case .exited(let code):
                                events = try parser.finish(exitCode: code, stderr: stderrTail)
                            }
                            for event in events where !completed {
                                if case .sessionStarted(let id?) = event { onSessionID(id) }
                                if case .completed = event {
                                    completed = true
                                    process.expectExit(within: exitGrace)
                                }
                                continuation.yield(event)
                            }
                        }
                    } catch {
                        // Whatever goes wrong after the answer does not unmake the answer.
                        if !completed { throw error }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            // Cancelling the task ends the loop over `process.output`, whose
            // termination handler kills the process group.
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

#endif
