import Foundation

/// One request to a CLI: a turn of a conversation, or a one-shot question.
struct AgentTurn: Sendable {
    enum Mode: Sendable, Equatable {
        /// Part of a conversation that later turns resume.
        case conversation
        /// A quick answer: no tools, nothing kept, low reasoning effort.
        case oneShot
    }

    var prompt: String
    var attachments: [URL] = []
    var config: AgentSessionConfig
    /// Native session id to continue; `nil` starts a new session.
    var resumeID: String?
    /// Id to give a new session, for CLIs that let the caller choose (Claude).
    var newSessionID = UUID().uuidString.lowercased()
    var mode: Mode = .conversation
}

struct AgentInvocation: Sendable, Equatable {
    var arguments: [String]
    var stdin: Data?
    var workingDirectory: URL
}

/// Everything CLI-specific: how to ask, and how to read the answer.
protocol AgentAdapter: Sendable {
    var kind: AgentKind { get }
    func invocation(for turn: AgentTurn) throws -> AgentInvocation
    func makeParser(for turn: AgentTurn) -> any AgentStreamParser
}

/// Turns one run's output into events. Stateful, used for a single run.
///
/// A parser reports failure by throwing `AgentError`, and success by returning
/// exactly one `.completed`, either from a line or from `finish`.
protocol AgentStreamParser {
    mutating func consume(stdout line: String) throws -> [AgentEvent]
    mutating func consume(stderr line: String) throws -> [AgentEvent]
    /// `stderr` is the tail of everything the process wrote to stderr.
    mutating func finish(exitCode: Int32, stderr: String) throws -> [AgentEvent]
}

extension AgentKind {
    var adapter: any AgentAdapter {
        switch self {
        case .claude: ClaudeAdapter()
        case .codex: CodexAdapter()
        case .antigravity: AntigravityAdapter()
        }
    }
}

// MARK: - Shared helpers

enum AgentJSON {
    static func object(_ line: String) -> [String: Any]? {
        guard line.first == "{", let data = line.data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    static func string(_ value: Any) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .withoutEscapingSlashes])) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }
}

/// Streams assistant text while keeping separate messages apart, and remembers
/// the last message, which is the answer when the CLI gives no explicit result.
struct AgentTextAccumulator {
    private(set) var lastMessage = ""
    private var hasEarlierMessage = false
    private var messageOpen = false

    /// Call when a new assistant message begins.
    mutating func beginMessage() {
        if messageOpen, !lastMessage.isEmpty { hasEarlierMessage = true }
        messageOpen = true
        lastMessage = ""
    }

    mutating func append(_ text: String) -> [AgentEvent] {
        guard !text.isEmpty else { return [] }
        if !messageOpen { beginMessage() }
        var events: [AgentEvent] = []
        if lastMessage.isEmpty, hasEarlierMessage { events.append(.textDelta("\n\n")) }
        lastMessage += text
        events.append(.textDelta(text))
        return events
    }

    func completed(preferring explicit: String?) -> AgentEvent {
        let text = (explicit?.isEmpty == false ? explicit! : lastMessage)
        return .completed(text: text.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}

enum AgentPaths {
    /// The path the kernel reports for `url`. `URL.resolvingSymlinksInPath`
    /// strips `/private`, which is exactly the prefix permission rules need.
    static func real(_ url: URL) -> String {
        guard let resolved = realpath(url.path, nil) else { return url.standardizedFileURL.path }
        defer { free(resolved) }
        return String(cString: resolved)
    }

    /// Both spellings of a directory, so a rule matches whichever one the
    /// agent uses (`/tmp/x` vs `/private/tmp/x`, iCloud symlinks).
    static func spellings(_ url: URL) -> [String] {
        var paths = [url.standardizedFileURL.path]
        let resolved = real(url)
        if !paths.contains(resolved) { paths.append(resolved) }
        return paths
    }
}

enum AgentActivity {
    static func reading(_ path: String?) -> String {
        guard let name = fileName(path) else { return "Reading a file" }
        return "Reading \(name)"
    }

    static func writing(_ path: String?) -> String {
        guard let name = fileName(path) else { return "Editing a file" }
        return "Editing \(name)"
    }

    static func searchingWeb(_ query: String?) -> String {
        guard let query, !query.isEmpty else { return "Searching the web" }
        return "Searching the web for \u{201C}\(clip(query, 80))\u{201D}"
    }

    static func fetching(_ url: String?) -> String {
        guard let url, let host = URL(string: url)?.host() else { return "Reading a web page" }
        return "Reading \(host)"
    }

    static func searchingFiles(_ pattern: String?) -> String {
        guard let pattern, !pattern.isEmpty else { return "Searching the book files" }
        return "Searching the book files for \u{201C}\(clip(pattern, 60))\u{201D}"
    }

    /// Describes a shell command the way a reader would: most of what agents
    /// run in a notes folder is `cat`, `sed -n` and `rg`.
    static func command(_ raw: String) -> String {
        var command = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        // Codex wraps everything as `/bin/zsh -lc '<command>'`.
        if let match = command.range(of: #"^\S*sh -l?c "#, options: .regularExpression) {
            command = String(command[match.upperBound...])
            if let quote = command.first, quote == "'" || quote == "\"", command.last == quote, command.count >= 2 {
                command = String(command.dropFirst().dropLast())
            }
        }
        let words = command.split(whereSeparator: \.isWhitespace).map(String.init)
        let unquote: (String) -> String = { $0.trimmingCharacters(in: CharacterSet(charactersIn: "'\"")) }
        switch words.first {
        case "cat", "head", "tail", "nl", "sed", "less", "bat":
            if let file = words.dropFirst().last(where: { !$0.hasPrefix("-") }).map(unquote), words.count > 1 {
                return reading(file)
            }
            return "Reading a file"
        case "rg", "grep", "find", "ls", "fd", "tree":
            return "Searching the book files"
        default:
            return "Running \(clip(command.replacingOccurrences(of: "\n", with: " "), 60))"
        }
    }

    private static func fileName(_ path: String?) -> String? {
        guard let path, !path.isEmpty else { return nil }
        let name = (path as NSString).lastPathComponent
        return name.isEmpty ? nil : name
    }

    private static func clip(_ text: String, _ limit: Int) -> String {
        text.count > limit ? String(text.prefix(limit)) + "\u{2026}" : text
    }
}
