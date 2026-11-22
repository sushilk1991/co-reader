import Foundation

/// A single quick answer ("what does this passage mean"): no tools, no session
/// kept, the CLI's lowest reasoning effort.
public struct AgentOneShot: Sendable {
    public let agent: DetectedAgent
    private let adapter: any AgentAdapter

    public init(agent: DetectedAgent) {
        self.init(agent: agent, adapter: agent.kind.adapter)
    }

    init(agent: DetectedAgent, adapter: any AgentAdapter) {
        self.agent = agent
        self.adapter = adapter
    }

    /// Throws `AgentError.timedOut` when no answer arrived within `timeout`.
    /// Cancelling the calling task kills the CLI.
    public func complete(
        _ prompt: String, workingDirectory: URL? = nil, timeout: Duration = .seconds(90)
    ) async throws -> String {
        #if os(macOS)
        // Somewhere empty by default, so the CLI finds no project files to load.
        let directory = workingDirectory ?? FileManager.default.temporaryDirectory
        let turn = AgentTurn(
            prompt: prompt,
            config: AgentSessionConfig(workingDirectory: directory, idleTimeout: timeout),
            mode: .oneShot
        )
        let events = AgentRun.events(adapter: adapter, executable: agent.executable, turn: turn, totalTimeout: timeout)
        for try await event in events {
            // Returning drops the stream, which kills the CLI: nothing is saved
            // in one-shot mode, so there is nothing to wait for.
            if case .completed(let text) = event { return text }
        }
        try Task.checkCancellation()
        throw AgentError.failed("\(agent.kind.displayName) stopped without an answer.")
        #else
        throw AgentError.notInstalled
        #endif
    }
}
