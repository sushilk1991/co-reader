import Foundation
import Testing
@testable import CoreaderKit

/// The flags each CLI is started with. These are the security boundary, so
/// they are pinned exactly.
@Suite struct AgentInvocationTests {
    let book = URL(fileURLWithPath: "/Users/reader/Coreader/Books/My Book, vol 1")
    let text = URL(fileURLWithPath: "/Users/reader/Library/Caches/Coreader/text/my-book")

    func turn(
        _ access: AgentAccess, resume: String? = nil, attachments: [URL] = [], model: String? = nil,
        systemPrompt: String = "You are a reading companion.", mode: AgentTurn.Mode = .conversation
    ) -> AgentTurn {
        AgentTurn(
            prompt: "What is attention?",
            attachments: attachments,
            config: AgentSessionConfig(
                workingDirectory: book, additionalDirectories: [text], systemPrompt: systemPrompt,
                access: access, model: model
            ),
            resumeID: resume,
            newSessionID: "11111111-2222-4333-8444-555555555555",
            mode: mode
        )
    }

    func value(after flag: String, in arguments: [String]) -> String? {
        arguments.firstIndex(of: flag).flatMap { $0 + 1 < arguments.count ? arguments[$0 + 1] : nil }
    }

    func values(after flag: String, in arguments: [String]) -> [String] {
        arguments.indices.filter { arguments[$0] == flag && $0 + 1 < arguments.count }.map { arguments[$0 + 1] }
    }

    @Test(arguments: AgentKind.allCases, [AgentAccess.readOnly, .canEditNotes])
    func noAdapterEverGrantsUnrestrictedAccess(kind: AgentKind, access: AgentAccess) throws {
        for resume in [nil, "abc"] as [String?] {
            let arguments = try kind.adapter.invocation(for: turn(access, resume: resume)).arguments
            let joined = arguments.joined(separator: " ")
            #expect(!joined.contains("dangerously"))
            #expect(!joined.contains("danger-full-access"))
            #expect(!joined.contains("bypassPermissions"))
            #expect(!arguments.contains("Bash"))
        }
    }

    // MARK: Claude

    @Test func claudeReadOnlyFirstTurn() throws {
        let invocation = try ClaudeAdapter().invocation(for: turn(.readOnly))
        #expect(invocation.arguments == [
            "-p", "--output-format", "stream-json", "--input-format", "stream-json", "--verbose",
            "--permission-mode", "dontAsk", "--safe-mode", "--strict-mcp-config", "--disable-slash-commands",
            "--include-partial-messages",
            "--tools", "Read,Glob,Grep,WebSearch,WebFetch",
            "--allowedTools", "WebSearch", "WebFetch",
            "--add-dir", text.path,
            "--session-id", "11111111-2222-4333-8444-555555555555",
            "--append-system-prompt", "You are a reading companion.",
        ])
        #expect(invocation.workingDirectory == book)
        let message = try #require(AgentJSON.object(String(decoding: invocation.stdin!, as: UTF8.self)))
        #expect(AgentJSON.string(message) == #"{"message":{"content":[{"text":"What is attention?","type":"text"}],"role":"user"},"type":"user"}"#)
        #expect(invocation.stdin?.last == 0x0A)
    }

    @Test func claudeCanEditNotesScopesWritesToTheWorkingDirectory() throws {
        let arguments = try ClaudeAdapter().invocation(for: turn(.canEditNotes)).arguments
        #expect(value(after: "--tools", in: arguments) == "Read,Glob,Grep,WebSearch,WebFetch,Edit,Write")
        // One argv element per rule, because the path has a space and a comma.
        #expect(arguments.contains("Edit(//Users/reader/Coreader/Books/My Book, vol 1/**)"))
        #expect(arguments.contains("Write(//Users/reader/Coreader/Books/My Book, vol 1/**)"))
        #expect(!arguments.contains { $0.hasPrefix("Edit(") && $0.contains("Caches") })
        #expect(!arguments.contains("Edit"))
        #expect(!arguments.contains("Write"))
        #expect(value(after: "--permission-mode", in: arguments) == "dontAsk")
    }

    @Test func claudeWriteRulesCoverTheResolvedPathToo() throws {
        // /var/folders/... is a symlink to /private/var/folders/...; Claude matches rules on the real path.
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("coreader-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        var request = turn(.canEditNotes)
        request.config.workingDirectory = directory
        let arguments = try ClaudeAdapter().invocation(for: request).arguments
        let real = AgentPaths.real(directory)
        #expect(real.hasPrefix("/private/"))
        #expect(arguments.contains("Write(/\(real)/**)"))
    }

    @Test func claudeResumedTurn() throws {
        let arguments = try ClaudeAdapter().invocation(for: turn(.readOnly, resume: "abc", model: "sonnet")).arguments
        #expect(value(after: "--resume", in: arguments) == "abc")
        #expect(!arguments.contains("--session-id"))
        #expect(value(after: "--model", in: arguments) == "sonnet")
    }

    @Test func claudeAttachesImagesAsBase64Blocks() throws {
        let image = FileManager.default.temporaryDirectory.appendingPathComponent("snip-\(UUID().uuidString).PNG")
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: image)
        defer { try? FileManager.default.removeItem(at: image) }
        let invocation = try ClaudeAdapter().invocation(for: turn(.readOnly, attachments: [image]))
        let message = try #require(AgentJSON.object(String(decoding: invocation.stdin!, as: UTF8.self)))
        let content = try #require((message["message"] as? [String: Any])?["content"] as? [[String: Any]])
        #expect(content.count == 2)
        let source = try #require(content[0]["source"] as? [String: String])
        #expect(source == ["type": "base64", "media_type": "image/png", "data": "iVBORw=="])
        #expect(content[1]["text"] as? String == "What is attention?")
    }

    @Test func claudeRejectsImagesItCannotRead() {
        #expect(throws: AgentError.self) {
            try ClaudeAdapter().invocation(for: turn(.readOnly, attachments: [URL(fileURLWithPath: "/tmp/snip.heic")]))
        }
        #expect(throws: AgentError.self) {
            try ClaudeAdapter().invocation(for: turn(.readOnly, attachments: [URL(fileURLWithPath: "/nonexistent/snip.png")]))
        }
    }

    @Test func claudeOneShotHasNoToolsAndKeepsNothing() throws {
        let arguments = try ClaudeAdapter().invocation(for: turn(.canEditNotes, systemPrompt: "", mode: .oneShot)).arguments
        #expect(arguments == [
            "-p", "--output-format", "stream-json", "--input-format", "stream-json", "--verbose",
            "--permission-mode", "dontAsk", "--safe-mode", "--strict-mcp-config", "--disable-slash-commands",
            "--tools", "", "--no-session-persistence", "--effort", "low",
        ])
    }

    // MARK: Codex

    @Test func codexReadOnlyFirstTurn() throws {
        let invocation = try CodexAdapter().invocation(for: turn(.readOnly))
        #expect(invocation.arguments == [
            "exec", "--json", "--skip-git-repo-check",
            "-c", #"sandbox_mode="read-only""#,
            "-c", "mcp_servers={}",
            "-c", #"web_search="live""#,
            "-c", #"developer_instructions="You are a reading companion.""#,
            "-",
        ])
        #expect(invocation.stdin == Data("What is attention?".utf8))
        #expect(invocation.workingDirectory == book)
    }

    @Test func codexCanEditNotesWritesOnlyInTheWorkingDirectory() throws {
        let arguments = try CodexAdapter().invocation(for: turn(.canEditNotes)).arguments
        let overrides = values(after: "-c", in: arguments)
        #expect(overrides.contains(#"sandbox_mode="workspace-write""#))
        #expect(overrides.contains("sandbox_workspace_write.exclude_slash_tmp=true"))
        #expect(overrides.contains("sandbox_workspace_write.exclude_tmpdir_env_var=true"))
        #expect(overrides.contains("sandbox_workspace_write.network_access=false"))
        // For Codex `--add-dir` means "also writable".
        #expect(!arguments.contains("--add-dir"))
    }

    @Test func codexResumedTurnWithImagesAndModel() throws {
        let image = URL(fileURLWithPath: "/tmp/a snip.png")
        let arguments = try CodexAdapter().invocation(
            for: turn(.readOnly, resume: "thread-1", attachments: [image], model: "gpt-x")
        ).arguments
        #expect(Array(arguments.prefix(3)) == ["exec", "resume", "thread-1"])
        // `exec resume` has no --sandbox or -C; the sandbox must still be pinned.
        #expect(!arguments.contains("-s") && !arguments.contains("--sandbox") && !arguments.contains("-C"))
        #expect(values(after: "-c", in: arguments).contains(#"sandbox_mode="read-only""#))
        #expect(value(after: "-m", in: arguments) == "gpt-x")
        #expect(value(after: "-i", in: arguments) == "/tmp/a snip.png")
        #expect(arguments.last == "-")
    }

    @Test func codexOneShotIsEphemeralAndReadOnly() throws {
        let arguments = try CodexAdapter().invocation(for: turn(.canEditNotes, resume: "x", systemPrompt: "", mode: .oneShot)).arguments
        #expect(arguments == [
            "exec", "--json", "--skip-git-repo-check", "--ephemeral",
            "-c", #"sandbox_mode="read-only""#,
            "-c", "mcp_servers={}",
            "-c", #"web_search="disabled""#,
            "-c", #"model_reasoning_effort="low""#,
            "-",
        ])
    }

    @Test func tomlStringsEscapeQuotesNewlinesAndControls() {
        #expect(CodexAdapter.toml("say \"hi\"\nC:\\path\ttab\u{01}é") == #""say \"hi\"\nC:\\path\ttab\u0001é""#)
    }

    // MARK: Antigravity

    func settings(_ arguments: [String]) throws -> (allow: [String], deny: [String]) {
        let json = try #require(value(after: "--settings", in: arguments))
        let permissions = try #require(AgentJSON.object(json)?["permissions"] as? [String: [String]])
        return (permissions["allow"] ?? [], permissions["deny"] ?? [])
    }

    @Test func antigravityReadOnlyFirstTurn() throws {
        let invocation = try AntigravityAdapter().invocation(for: turn(.readOnly))
        let arguments = invocation.arguments
        #expect(Array(arguments.prefix(2)) == ["-p", "You are a reading companion.\n\n---\n\nWhat is attention?"])
        #expect(value(after: "--output-format", in: arguments) == "stream-json")
        #expect(arguments.contains("--sandbox"))
        // Plan mode makes it plan instead of answer; --add-dir would make the directory writable.
        #expect(!arguments.contains("--mode") && !arguments.contains("--add-dir") && !arguments.contains("--conversation"))
        let rules = try settings(arguments)
        #expect(rules.deny == ["write_file(*)", "command(*)"])
        #expect(rules.allow == ["read_file(/Users/reader/Library/Caches/Coreader/text/my-book/**)"])
        #expect(invocation.stdin == nil)
        #expect(invocation.workingDirectory == book)
    }

    @Test func antigravityCanEditNotesStillDeniesCommands() throws {
        let rules = try settings(AntigravityAdapter().invocation(for: turn(.canEditNotes)).arguments)
        #expect(rules.deny == ["command(*)"])
        #expect(!rules.allow.contains { $0.hasPrefix("write_file") })
    }

    @Test func antigravityResumedTurnDoesNotRepeatTheSystemPrompt() throws {
        let arguments = try AntigravityAdapter().invocation(for: turn(.readOnly, resume: "conv-1", model: "gemini-x")).arguments
        #expect(arguments[1] == "What is attention?")
        #expect(value(after: "--conversation", in: arguments) == "conv-1")
        #expect(value(after: "--model", in: arguments) == "gemini-x")
    }

    @Test func antigravityAttachmentsAreNamedInThePromptAndMadeReadable() throws {
        let image = URL(fileURLWithPath: "/Users/reader/snips/a snip.png")
        let arguments = try AntigravityAdapter().invocation(for: turn(.readOnly, resume: "c", attachments: [image])).arguments
        #expect(arguments[1].hasSuffix("- /Users/reader/snips/a snip.png"))
        #expect(try settings(arguments).allow.contains("read_file(/Users/reader/snips/a snip.png)"))
    }

    @Test func antigravityRefusesPromptsTooLongForArgv() {
        var request = turn(.readOnly)
        request.prompt = String(repeating: "x", count: AntigravityAdapter.maximumPromptBytes + 1)
        #expect(throws: AgentError.self) { try AntigravityAdapter().invocation(for: request) }
    }

    @Test func antigravityOnlyChecksTheConversationWhenResuming() {
        let fresh = AntigravityAdapter().makeParser(for: turn(.readOnly)) as? AntigravityStreamParser
        let resumed = AntigravityAdapter().makeParser(for: turn(.readOnly, resume: "conv-1")) as? AntigravityStreamParser
        #expect(fresh?.expectedConversation == nil)
        #expect(resumed?.expectedConversation == "conv-1")
    }

    @Test func kindsHaveTheDocumentedNames() {
        #expect(AgentKind.allCases.map(\.displayName) == ["Claude Code", "Codex", "Antigravity"])
        #expect(AgentKind.allCases.map(\.executableName) == ["claude", "codex", "agy"])
    }
}
