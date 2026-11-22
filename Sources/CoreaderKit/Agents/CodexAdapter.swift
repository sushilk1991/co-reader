import Foundation

/// OpenAI Codex (`codex exec --json`), verified against codex-cli 0.170.0.
///
/// The prompt is read from stdin (`-`). `exec resume` has no `--sandbox` or
/// `-C`, so the sandbox is always set through `-c` overrides, which both
/// subcommands accept, and the working directory is the process's own.
struct CodexAdapter: AgentAdapter {
    let kind = AgentKind.codex

    func invocation(for turn: AgentTurn) throws -> AgentInvocation {
        let config = turn.config
        var arguments = ["exec"]
        if turn.mode == .conversation, let resumeID = turn.resumeID {
            arguments += ["resume", resumeID]
        }
        // A book folder is not a git repository.
        arguments += ["--json", "--skip-git-repo-check"]

        let writable = turn.mode == .conversation && config.access == .canEditNotes
        var overrides = [
            "sandbox_mode=\(Self.toml(writable ? "workspace-write" : "read-only"))",
            // The reader's MCP servers run outside the sandbox; leave them out.
            "mcp_servers={}",
        ]
        if writable {
            // By default workspace-write also opens /tmp and $TMPDIR. Only the
            // working directory should be writable. Added directories are not
            // passed as `--add-dir`: for Codex that flag means "also writable",
            // and the sandbox already lets it read anywhere.
            overrides += [
                "sandbox_workspace_write.exclude_slash_tmp=true",
                "sandbox_workspace_write.exclude_tmpdir_env_var=true",
                "sandbox_workspace_write.network_access=false",
            ]
        }
        switch turn.mode {
        case .conversation:
            overrides.append("web_search=\(Self.toml("live"))")
        case .oneShot:
            arguments.append("--ephemeral")
            overrides += ["web_search=\(Self.toml("disabled"))", "model_reasoning_effort=\(Self.toml("low"))"]
        }
        if !config.systemPrompt.isEmpty {
            overrides.append("developer_instructions=\(Self.toml(config.systemPrompt))")
        }
        for override in overrides { arguments += ["-c", override] }

        if let model = config.model, !model.isEmpty {
            arguments += ["-m", model]
        }
        for attachment in turn.attachments {
            arguments += ["-i", attachment.path]
        }
        arguments.append("-")

        return AgentInvocation(
            arguments: arguments, stdin: Data(turn.prompt.utf8), workingDirectory: config.workingDirectory
        )
    }

    func makeParser(for turn: AgentTurn) -> any AgentStreamParser { CodexStreamParser() }

    /// A TOML basic string. `-c` values are parsed as TOML, and a system
    /// prompt has quotes and newlines in it.
    static func toml(_ value: String) -> String {
        var out = "\""
        for scalar in value.unicodeScalars {
            switch scalar {
            case "\\": out += "\\\\"
            case "\"": out += "\\\""
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            default:
                if scalar.value < 0x20 || scalar.value == 0x7F {
                    out += String(format: "\\u%04X", scalar.value)
                } else {
                    out.unicodeScalars.append(scalar)
                }
            }
        }
        return out + "\""
    }
}

/// Codex emits whole messages (`item.completed`), not token deltas.
struct CodexStreamParser: AgentStreamParser {
    private var text = AgentTextAccumulator()
    private var failure: String?
    private var completed = false

    mutating func consume(stdout line: String) throws -> [AgentEvent] {
        guard let object = AgentJSON.object(line), let type = object["type"] as? String else { return [] }
        switch type {
        case "thread.started":
            return [.sessionStarted(id: object["thread_id"] as? String)]

        case "item.started", "item.completed":
            guard let item = object["item"] as? [String: Any], let itemType = item["type"] as? String else { return [] }
            let finished = type == "item.completed"
            switch itemType {
            case "agent_message":
                guard finished, let message = item["text"] as? String else { return [] }
                text.beginMessage()
                return text.append(message)
            case "command_execution":
                guard !finished, let command = item["command"] as? String else { return [] }
                return [.activity(AgentActivity.command(command))]
            case "web_search":
                // The query is only known once the search has run.
                let query = item["query"] as? String ?? ""
                if finished { return query.isEmpty ? [] : [.activity(AgentActivity.searchingWeb(query))] }
                return [.activity(AgentActivity.searchingWeb(nil))]
            case "file_change":
                guard finished else { return [] }
                let path = (item["changes"] as? [[String: Any]])?.first?["path"] as? String
                return [.activity(AgentActivity.writing(path))]
            case "reasoning":
                return finished ? [] : [.activity("Thinking")]
            case "error":
                try throwIfSignedOut(item["message"] as? String)
                return []
            default:
                return []
            }

        case "error":
            // Transient: Codex retries ("Reconnecting... 2/5") before it gives up.
            // Signed out is not transient, and the retries take half a minute.
            try throwIfSignedOut(object["message"] as? String)
            return [.activity("Reconnecting")]

        case "turn.failed":
            failure = (object["error"] as? [String: Any])?["message"] as? String ?? "Codex could not finish this turn."
            return []

        case "turn.completed":
            completed = true
            return [text.completed(preferring: nil)]

        default:
            return []
        }
    }

    mutating func consume(stderr line: String) throws -> [AgentEvent] { [] }

    mutating func finish(exitCode: Int32, stderr: String) throws -> [AgentEvent] {
        if completed { return [] }
        if let failure { throw AgentError.classify(failure, kind: .codex) }
        if exitCode != 0 { throw AgentError.classify(Self.meaningful(stderr), kind: .codex) }
        return [text.completed(preferring: nil)]
    }

    private func throwIfSignedOut(_ message: String?) throws {
        guard let message else { return }
        if case .notSignedIn = AgentError.classify(message, kind: .codex) { throw AgentError.signedOut(.codex) }
    }

    /// Codex logs timestamped tracing lines to stderr; the line a person can
    /// act on is the one starting with "Error:".
    static func meaningful(_ stderr: String) -> String {
        let lines = stderr.split(separator: "\n").map(String.init)
        if let error = lines.last(where: { $0.hasPrefix("Error:") || $0.hasPrefix("error:") }) {
            return String(error.drop(while: { $0 != ":" }).dropFirst()).trimmingCharacters(in: .whitespaces)
        }
        return lines.suffix(3).joined(separator: "\n")
    }
}
