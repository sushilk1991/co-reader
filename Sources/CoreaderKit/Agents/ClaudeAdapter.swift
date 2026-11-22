import Foundation

/// Claude Code (`claude -p`), verified against 2.1.330.
///
/// The prompt goes in as one stream-json user message on stdin: that is the
/// only way to attach images in print mode, and it keeps prompts off argv.
struct ClaudeAdapter: AgentAdapter {
    let kind = AgentKind.claude

    static let readTools = ["Read", "Glob", "Grep", "WebSearch", "WebFetch"]
    static let writeTools = ["Edit", "Write"]

    func invocation(for turn: AgentTurn) throws -> AgentInvocation {
        let config = turn.config
        var arguments = [
            "-p", "--output-format", "stream-json", "--input-format", "stream-json", "--verbose",
            // Anything not explicitly allowed is refused instead of prompting.
            "--permission-mode", "dontAsk",
            // The reader's own hooks, CLAUDE.md, skills and MCP servers (mail,
            // chat, browsers) have no business in a book conversation.
            "--safe-mode", "--strict-mcp-config", "--disable-slash-commands",
        ]

        switch turn.mode {
        case .oneShot:
            arguments += ["--tools", "", "--no-session-persistence", "--effort", "low"]
        case .conversation:
            arguments.append("--include-partial-messages")
            var tools = Self.readTools
            // Reading inside the working and added directories needs no rule;
            // deliberately no blanket `Read`, which would open the whole disk.
            var allowed = ["WebSearch", "WebFetch"]
            if config.access == .canEditNotes {
                tools += Self.writeTools
                for path in AgentPaths.spellings(config.workingDirectory) {
                    // `//` anchors a rule at the filesystem root.
                    allowed += Self.writeTools.map { "\($0)(/\(path)/**)" }
                }
            }
            arguments += ["--tools", tools.joined(separator: ",")]
            // One argv element per rule: the CLI splits a single value on
            // spaces and commas, and library paths contain both.
            arguments.append("--allowedTools")
            arguments += allowed
            for directory in config.additionalDirectories {
                arguments += ["--add-dir", directory.path]
            }
            if let resumeID = turn.resumeID {
                arguments += ["--resume", resumeID]
            } else {
                arguments += ["--session-id", turn.newSessionID]
            }
        }

        if !config.systemPrompt.isEmpty {
            arguments += ["--append-system-prompt", config.systemPrompt]
        }
        if let model = config.model, !model.isEmpty {
            arguments += ["--model", model]
        }

        var content: [[String: Any]] = []
        for attachment in turn.attachments {
            guard let mediaType = Self.mediaType(for: attachment) else {
                throw AgentError.failed("Claude Code cannot read \(attachment.lastPathComponent): only PNG, JPEG, GIF and WebP images can be attached.")
            }
            guard let data = try? Data(contentsOf: attachment) else {
                throw AgentError.failed("The attached image \(attachment.lastPathComponent) could not be read.")
            }
            content.append([
                "type": "image",
                "source": ["type": "base64", "media_type": mediaType, "data": data.base64EncodedString()],
            ])
        }
        content.append(["type": "text", "text": turn.prompt])
        let message: [String: Any] = ["type": "user", "message": ["role": "user", "content": content]]
        var stdin = try JSONSerialization.data(withJSONObject: message)
        stdin.append(0x0A)

        return AgentInvocation(arguments: arguments, stdin: stdin, workingDirectory: config.workingDirectory)
    }

    func makeParser(for turn: AgentTurn) -> any AgentStreamParser { ClaudeStreamParser() }

    static func mediaType(for url: URL) -> String? {
        switch url.pathExtension.lowercased() {
        case "png": "image/png"
        case "jpg", "jpeg": "image/jpeg"
        case "gif": "image/gif"
        case "webp": "image/webp"
        default: nil
        }
    }
}

struct ClaudeStreamParser: AgentStreamParser {
    private var text = AgentTextAccumulator()
    /// Text deltas seen since the current message started. Zero when the CLI
    /// ran without partial messages, in which case whole messages are emitted.
    private var streamedCharacters = 0
    private var failure: String?
    private var completed = false

    mutating func consume(stdout line: String) throws -> [AgentEvent] {
        guard let object = AgentJSON.object(line), let type = object["type"] as? String else { return [] }
        // Subagent chatter is not part of the answer.
        if object["parent_tool_use_id"] is String { return [] }

        switch type {
        case "system":
            guard object["subtype"] as? String == "init" else { return [] }
            return [.sessionStarted(id: object["session_id"] as? String)]

        case "stream_event":
            guard let event = object["event"] as? [String: Any], let eventType = event["type"] as? String else { return [] }
            switch eventType {
            case "message_start":
                text.beginMessage()
                streamedCharacters = 0
            case "content_block_start":
                if (event["content_block"] as? [String: Any])?["type"] as? String == "thinking" {
                    return [.activity("Thinking")]
                }
            case "content_block_delta":
                guard let delta = event["delta"] as? [String: Any], delta["type"] as? String == "text_delta",
                      let chunk = delta["text"] as? String else { return [] }
                streamedCharacters += chunk.count
                return text.append(chunk)
            default:
                break
            }
            return []

        case "assistant":
            guard let message = object["message"] as? [String: Any],
                  let blocks = message["content"] as? [[String: Any]] else { return [] }
            var events: [AgentEvent] = []
            for block in blocks {
                switch block["type"] as? String {
                case "tool_use":
                    events.append(.activity(Self.activity(
                        tool: block["name"] as? String ?? "", input: block["input"] as? [String: Any] ?? [:]
                    )))
                case "text":
                    // "Not logged in" arrives as a synthetic assistant message;
                    // the result line that follows turns it into an error.
                    if streamedCharacters == 0, let whole = block["text"] as? String, message["model"] as? String != "<synthetic>" {
                        text.beginMessage()
                        events += text.append(whole)
                    }
                default:
                    break
                }
            }
            return events

        case "result":
            if object["is_error"] as? Bool == true {
                let errors = (object["errors"] as? [String])?.joined(separator: "\n")
                failure = [object["result"] as? String, errors].compactMap { $0 }.joined(separator: "\n")
                return []
            }
            completed = true
            return [text.completed(preferring: object["result"] as? String)]

        default:
            return []
        }
    }

    mutating func consume(stderr line: String) throws -> [AgentEvent] { [] }

    mutating func finish(exitCode: Int32, stderr: String) throws -> [AgentEvent] {
        if completed { return [] }
        if let failure { throw AgentError.classify(failure + "\n" + stderr, kind: .claude) }
        if exitCode != 0 { throw AgentError.classify(stderr, kind: .claude) }
        return [text.completed(preferring: nil)]
    }

    static func activity(tool: String, input: [String: Any]) -> String {
        switch tool {
        case "Read": AgentActivity.reading(input["file_path"] as? String)
        case "Edit", "Write": AgentActivity.writing(input["file_path"] as? String)
        case "Grep": AgentActivity.searchingFiles(input["pattern"] as? String)
        case "Glob": AgentActivity.searchingFiles(nil)
        case "WebSearch": AgentActivity.searchingWeb(input["query"] as? String)
        case "WebFetch": AgentActivity.fetching(input["url"] as? String)
        default: "Using \(tool)"
        }
    }
}
