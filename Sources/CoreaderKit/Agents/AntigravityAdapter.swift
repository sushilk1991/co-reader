import Foundation

/// Google Antigravity (`agy -p`), verified against 1.5.13.
///
/// Traps found by running it:
/// - `--mode plan` is not a read-only mode for questions: the agent tries to
///   draft an implementation plan and runs shell commands to do it.
/// - In print mode a tool that would need approval is denied and the turn
///   ends with an EMPTY response. Explicit deny rules avoid that: the agent
///   sees a normal tool error and carries on. So everything Coreader never
///   allows is denied by rule instead of left to the prompt.
/// - `--add-dir` makes a directory writable as well as readable, so added
///   directories are granted through `read_file(...)` allow rules instead.
/// - There is no system-prompt flag and no image flag.
struct AntigravityAdapter: AgentAdapter {
    let kind = AgentKind.antigravity

    /// The prompt travels on argv; macOS caps argv plus environment at 1 MB.
    static let maximumPromptBytes = 400_000

    func invocation(for turn: AgentTurn) throws -> AgentInvocation {
        let config = turn.config
        let writable = turn.mode == .conversation && config.access == .canEditNotes

        var allow: [String] = []
        for directory in config.additionalDirectories {
            allow += AgentPaths.spellings(directory).map { "read_file(\($0)/**)" }
        }
        for attachment in turn.attachments {
            allow += AgentPaths.spellings(attachment).map { "read_file(\($0))" }
        }
        // Writes inside the working directory are allowed by default; writes
        // anywhere else are refused because nothing can approve them.
        let deny = writable ? ["command(*)"] : ["write_file(*)", "command(*)"]
        let settings = AgentJSON.string(["permissions": ["allow": allow, "deny": deny]])

        var prompt = turn.prompt
        if !turn.attachments.isEmpty {
            prompt += "\n\nAttached images (open each with your file-reading tool before answering):\n"
            prompt += turn.attachments.map { "- \($0.path)" }.joined(separator: "\n")
        }
        if turn.resumeID == nil, !config.systemPrompt.isEmpty {
            prompt = config.systemPrompt + "\n\n---\n\n" + prompt
        }
        guard prompt.utf8.count <= Self.maximumPromptBytes else {
            throw AgentError.failed("That message is too long for Antigravity. Shorten it or attach the text as a file.")
        }

        var arguments = ["-p", prompt, "--output-format", "stream-json", "--sandbox", "--settings", settings]
        if let model = config.model, !model.isEmpty {
            arguments += ["--model", model]
        }
        switch turn.mode {
        case .conversation:
            if let resumeID = turn.resumeID { arguments += ["--conversation", resumeID] }
        case .oneShot:
            arguments += ["--effort", "low"]
        }
        return AgentInvocation(arguments: arguments, stdin: nil, workingDirectory: config.workingDirectory)
    }

    func makeParser(for turn: AgentTurn) -> any AgentStreamParser {
        AntigravityStreamParser(expectedConversation: turn.mode == .conversation ? turn.resumeID : nil)
    }
}

struct AntigravityStreamParser: AgentStreamParser {
    /// `--conversation <unknown id>` only prints a warning and silently starts
    /// a NEW conversation, so the id it reports has to be checked.
    var expectedConversation: String?

    private var text = AgentTextAccumulator()
    private var textStep: Int?
    private var completed = false

    mutating func consume(stdout line: String) throws -> [AgentEvent] {
        guard let object = AgentJSON.object(line), let event = object["event"] as? String else { return [] }
        switch event {
        case "init":
            let id = object["conversation_id"] as? String
            if let expectedConversation, let id, id != expectedConversation { throw AgentError.sessionMissing }
            return [.sessionStarted(id: id)]

        case "step_update":
            guard let step = object["step_update"] as? [String: Any] else { return [] }
            switch step["step_type"] as? String {
            case "agent_response":
                guard let delta = step["text_delta"] as? String else { return [] }
                let index = step["step_index"] as? Int
                if index != textStep {
                    textStep = index
                    text.beginMessage()
                }
                return text.append(delta)
            case "tool":
                guard step["state"] as? String == "ACTIVE" else { return [] }
                let info = step["tool_info"] as? [String: Any]
                return [.activity(Self.activity(
                    tool: step["tool_name"] as? String ?? info?["name"] as? String ?? "",
                    parameters: info?["parameters"] as? [String: Any] ?? [:]
                ))]
            default:
                return []
            }

        case "result":
            guard let result = object["result"] as? [String: Any] else { return [] }
            if result["status"] as? String != "SUCCESS" {
                throw AgentError.classify(result["error"] as? String ?? "", kind: .antigravity)
            }
            let response = result["response"] as? String ?? ""
            let denied = (result["denied_actions"] as? [[String: Any]] ?? []).compactMap { $0["display_name"] as? String }
            if response.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !denied.isEmpty {
                throw AgentError.failed(
                    "Antigravity stopped because it tried something Coreader does not allow (\(denied.joined(separator: ", "))). Ask again, and say which files it should use."
                )
            }
            completed = true
            return [text.completed(preferring: response)]

        default:
            return []
        }
    }

    mutating func consume(stderr line: String) throws -> [AgentEvent] {
        // Signed out, it prints a login URL and waits for a browser sign-in
        // that nobody is going to do from here.
        if line.hasPrefix("Authentication required") { throw AgentError.signedOut(.antigravity) }
        if expectedConversation != nil, line.hasPrefix("warning: conversation"), line.hasSuffix("not found") {
            throw AgentError.sessionMissing
        }
        return []
    }

    mutating func finish(exitCode: Int32, stderr: String) throws -> [AgentEvent] {
        if completed { return [] }
        if exitCode != 0 { throw AgentError.classify(stderr, kind: .antigravity) }
        return [text.completed(preferring: nil)]
    }

    static func activity(tool: String, parameters: [String: Any]) -> String {
        func parameter(_ names: String...) -> String? {
            names.lazy.compactMap { parameters[$0] as? String }.first
        }
        switch tool {
        case "read_file", "view_file":
            return AgentActivity.reading(parameter("Path", "AbsolutePath"))
        case "write_file", "edit_file", "write_to_file", "replace_file_content", "multi_replace_file_content", "sed_file":
            return AgentActivity.writing(parameter("Path", "TargetFile"))
        case "search_web":
            return AgentActivity.searchingWeb(parameter("query", "Query"))
        case "read_url_content":
            return AgentActivity.fetching(parameter("Url", "url"))
        case "grep_search":
            return AgentActivity.searchingFiles(parameter("Query", "query"))
        case "find_by_name", "list_dir":
            return AgentActivity.searchingFiles(nil)
        case "run_command":
            return AgentActivity.command(parameter("CommandLine") ?? "a command")
        default:
            return "Using \(tool.replacingOccurrences(of: "_", with: " "))"
        }
    }
}
