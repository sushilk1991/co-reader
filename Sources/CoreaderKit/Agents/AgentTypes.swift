import Foundation

/// The coding-agent CLIs Coreader can drive for its AI side panel.
public enum AgentKind: String, Codable, Sendable, CaseIterable, Identifiable {
    case claude, codex, antigravity

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .claude: "Claude Code"
        case .codex: "Codex"
        case .antigravity: "Antigravity"
        }
    }

    public var executableName: String {
        switch self {
        case .claude: "claude"
        case .codex: "codex"
        case .antigravity: "agy"
        }
    }
}

public struct DetectedAgent: Sendable, Identifiable, Hashable {
    public var kind: AgentKind
    public var executable: URL
    public var version: String?
    public var id: AgentKind { kind }

    public init(kind: AgentKind, executable: URL, version: String? = nil) {
        self.kind = kind
        self.executable = executable
        self.version = version
    }
}

/// What the agent may touch. Neither level lets it run shell commands with
/// network access or write outside the working directory.
public enum AgentAccess: Sendable, Hashable {
    /// Read files in the working directory and the added directories, search the web.
    case readOnly
    /// `readOnly`, plus create and edit files inside the working directory.
    case canEditNotes
}

public struct AgentSessionConfig: Sendable {
    public var workingDirectory: URL
    public var additionalDirectories: [URL]
    /// Appended to the agent's own system prompt where the CLI supports it
    /// (Claude, Codex); otherwise prefixed to the first user turn (Antigravity).
    public var systemPrompt: String
    public var access: AgentAccess
    /// `nil` uses the model the CLI is configured with.
    public var model: String?
    /// The turn fails with `AgentError.timedOut` after this long without any
    /// output. Not a cap on the whole turn: agent turns legitimately take minutes.
    public var idleTimeout: Duration

    public init(
        workingDirectory: URL,
        additionalDirectories: [URL] = [],
        systemPrompt: String = "",
        access: AgentAccess = .readOnly,
        model: String? = nil,
        idleTimeout: Duration = .seconds(300)
    ) {
        self.workingDirectory = workingDirectory
        self.additionalDirectories = additionalDirectories
        self.systemPrompt = systemPrompt
        self.access = access
        self.model = model
        self.idleTimeout = idleTimeout
    }
}

public enum AgentEvent: Sendable, Equatable {
    /// The CLI reported its native session id (also available as `AgentSession.sessionID`).
    case sessionStarted(id: String?)
    /// Incremental assistant text. Includes interim commentary the agent writes
    /// between tool calls; separate messages are divided by a blank line.
    case textDelta(String)
    /// Short human-readable status, e.g. "Reading 012-attention.md".
    case activity(String)
    /// The final answer of this turn. Always the last event of a successful turn.
    case completed(text: String)
}

public enum AgentError: Error, Sendable, Equatable, LocalizedError {
    case notInstalled
    /// The associated value is a user-presentable sentence saying how to sign in.
    case notSignedIn(String)
    case timedOut
    case failed(String)
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .notInstalled: "This agent is not installed on this Mac."
        case .notSignedIn(let message): message
        case .timedOut: "The agent stopped responding."
        case .failed(let message): message
        case .cancelled: "Stopped."
        }
    }

    /// The saved conversation is gone (deleted, expired, or created in another
    /// folder). Start a new `AgentSession` without `resuming:`.
    public var isSessionMissing: Bool { self == Self.sessionMissing }

    static let sessionMissing = AgentError.failed(
        "This conversation can no longer be continued because the agent no longer has it. Start a new conversation."
    )

    static func signedOut(_ kind: AgentKind) -> AgentError {
        .notSignedIn(
            "\(kind.displayName) is not signed in. Open Terminal, run \u{201C}\(kind.executableName)\u{201D} and sign in, then try again."
        )
    }

    /// Turns raw CLI error text into the most specific error. `kind` is only
    /// used to word the sign-in hint.
    static func classify(_ text: String, kind: AgentKind) -> AgentError {
        let lower = text.lowercased()
        let missing = ["no conversation found", "no rollout found", "session not found", "conversation not found"]
        if missing.contains(where: lower.contains) || lower.range(of: #"conversation "[^"]*" not found"#, options: .regularExpression) != nil {
            return sessionMissing
        }
        let signedOut = [
            "not logged in", "please run /login", "401 unauthorized", "authentication required",
            "authentication failed", "invalid api key", "not authenticated", "codex login", "oauth token has expired",
        ]
        if signedOut.contains(where: lower.contains) { return .signedOut(kind) }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .failed("\(kind.displayName) stopped without an answer.") }
        // Raw stderr can be pages long; the panel shows this in one line or two.
        return .failed(trimmed.count > 600 ? String(trimmed.prefix(600)) + "\u{2026}" : trimmed)
    }
}
