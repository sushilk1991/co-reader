#if os(macOS)
import Foundation
import Testing
@testable import CoreaderKit

/// Real conversations with the CLIs installed on this Mac. They cost tokens
/// and need the network and a signed-in CLI, so they only run on request:
///
///     COREADER_LIVE_AGENTS=1 swift test --filter AgentLiveTests
///
/// An agent that is not installed is reported and skipped, not failed.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["COREADER_LIVE_AGENTS"] == "1"), .serialized)
struct AgentLiveTests {
    struct Turn {
        var events: [AgentEvent] = []
        var firstText: Duration?
        var total: Duration = .zero

        var answer: String {
            if case .completed(let text) = events.last { text } else { "" }
        }
        var deltas: Int { events.count { if case .textDelta = $0 { true } else { false } } }
        var activities: [String] { events.compactMap { if case .activity(let label) = $0 { label } else { nil } } }
    }

    func run(_ session: AgentSession, _ prompt: String, attachments: [URL] = []) async throws -> Turn {
        var turn = Turn()
        let started = ContinuousClock.now
        for try await event in session.send(prompt, attachments: attachments) {
            if case .textDelta = event, turn.firstText == nil { turn.firstText = .now - started }
            turn.events.append(event)
        }
        turn.total = .now - started
        return turn
    }

    func agent(_ kind: AgentKind) async -> DetectedAgent? {
        let agent = await AgentDetector().detect().first { $0.kind == kind }
        if agent == nil { print("LIVE \(kind.rawValue): not installed, skipped") }
        return agent
    }

    /// A book folder outside /tmp, which Codex's sandbox treats specially.
    func makeBook() throws -> (book: URL, extra: URL, root: URL) {
        let root = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Caches/Coreader-live-tests/\(UUID().uuidString)")
        let book = root.appendingPathComponent("Books/My Book, vol 1")
        let extra = root.appendingPathComponent("extracted text")
        try FileManager.default.createDirectory(at: book, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: extra, withIntermediateDirectories: true)
        try "# Notes\n\n- The secret code is MANGO-42.\n".write(to: book.appendingPathComponent("notes.md"), atomically: true, encoding: .utf8)
        try "Chapter 1. The hidden word is KIWI-7.\n".write(to: extra.appendingPathComponent("001.md"), atomically: true, encoding: .utf8)
        return (book, extra, root)
    }

    @Test func detectsInstalledAgents() async {
        let agents = await AgentDetector().detect()
        for agent in agents {
            print("LIVE detect: \(agent.kind.rawValue) at \(agent.executable.path) version \(agent.version ?? "?")")
            #expect(agent.version != nil)
        }
    }

    @Test(arguments: AgentKind.allCases)
    func secondTurnRemembersTheFirst(kind: AgentKind) async throws {
        guard let agent = await agent(kind) else { return }
        let (book, extra, root) = try makeBook()
        defer { try? FileManager.default.removeItem(at: root) }
        let config = AgentSessionConfig(
            workingDirectory: book, additionalDirectories: [extra],
            systemPrompt: "You are a reading companion inside the Coreader app. Keep answers to one short sentence.",
            access: .readOnly
        )

        let session = AgentSession(agent: agent, config: config)
        let first = try await run(session, "Remember the word PINEAPPLE. Also read notes.md and tell me the secret code.")
        print("LIVE \(kind.rawValue) turn 1: first text \(first.firstText.map { "\($0)" } ?? "none"), total \(first.total), \(first.deltas) deltas, activities \(first.activities), answer: \(first.answer)")
        #expect(first.answer.contains("MANGO-42"))
        #expect(first.events.contains { if case .sessionStarted = $0 { true } else { false } })
        let id = try #require(session.sessionID)

        // A new object with only the stored id, as the app does after a relaunch.
        let resumed = AgentSession(agent: agent, config: config, resuming: id)
        let second = try await run(resumed, "What was the word I asked you to remember? Answer with just the word.")
        print("LIVE \(kind.rawValue) turn 2: first text \(second.firstText.map { "\($0)" } ?? "none"), total \(second.total), \(second.deltas) deltas, answer: \(second.answer)")
        #expect(second.answer.uppercased().contains("PINEAPPLE"))
        #expect(resumed.sessionID == id)
    }

    @Test(arguments: AgentKind.allCases)
    func readOnlyCannotWriteButCanReadAddedDirectories(kind: AgentKind) async throws {
        guard let agent = await agent(kind) else { return }
        let (book, extra, root) = try makeBook()
        defer { try? FileManager.default.removeItem(at: root) }
        let session = AgentSession(agent: agent, config: AgentSessionConfig(
            workingDirectory: book, additionalDirectories: [extra], access: .readOnly
        ))
        let turn = try await run(session, """
            Do both of these, then report: 1) read the file \(extra.path)/001.md and tell me the hidden word. \
            2) create a file named blocked.md in the current directory containing the letter x.
            """)
        print("LIVE \(kind.rawValue) read-only: activities \(turn.activities), answer: \(turn.answer)")
        #expect(turn.answer.contains("KIWI-7"))
        #expect(!FileManager.default.fileExists(atPath: book.appendingPathComponent("blocked.md").path))
    }

    @Test(arguments: AgentKind.allCases)
    func canEditNotesWritesOnlyInsideTheWorkingDirectory(kind: AgentKind) async throws {
        guard let agent = await agent(kind) else { return }
        let (book, extra, root) = try makeBook()
        defer { try? FileManager.default.removeItem(at: root) }
        let session = AgentSession(agent: agent, config: AgentSessionConfig(
            workingDirectory: book, additionalDirectories: [extra], access: .canEditNotes
        ))
        let inside = try await run(session, "Append the line '- added by the agent' to notes.md in the current directory, then say done.")
        print("LIVE \(kind.rawValue) edit inside: activities \(inside.activities), answer: \(inside.answer)")
        let notes = try String(contentsOf: book.appendingPathComponent("notes.md"), encoding: .utf8)
        #expect(notes.contains("added by the agent"))
        #expect(notes.contains("MANGO-42"))

        // Antigravity ends the turn with an error when an action is refused; either way no file may appear.
        let outside = try? await run(session, "Create the file \(extra.path)/outside.md containing the letter x, then say whether it worked.")
        print("LIVE \(kind.rawValue) edit outside: \(outside?.answer ?? "turn failed (refused)")")
        #expect(!FileManager.default.fileExists(atPath: extra.appendingPathComponent("outside.md").path))
    }

    @Test(arguments: AgentKind.allCases)
    func seesAnAttachedImage(kind: AgentKind) async throws {
        guard let agent = await agent(kind) else { return }
        let (book, _, root) = try makeBook()
        defer { try? FileManager.default.removeItem(at: root) }
        let image = root.appendingPathComponent("snip red.png")
        try Self.solidPNG(red: 255, green: 0, blue: 0).write(to: image)
        let session = AgentSession(agent: agent, config: AgentSessionConfig(workingDirectory: book))
        let turn = try await run(session, "What single colour fills the attached image? Answer with one word.", attachments: [image])
        print("LIVE \(kind.rawValue) image: \(turn.answer)")
        #expect(turn.answer.lowercased().contains("red"))
    }

    @Test(arguments: AgentKind.allCases)
    func aStaleSessionIDIsReportedAsMissing(kind: AgentKind) async throws {
        guard let agent = await agent(kind) else { return }
        let (book, _, root) = try makeBook()
        defer { try? FileManager.default.removeItem(at: root) }
        let session = AgentSession(
            agent: agent, config: AgentSessionConfig(workingDirectory: book),
            resuming: "00000000-0000-4000-8000-000000000000"
        )
        let error = await #expect(throws: AgentError.self) { _ = try await run(session, "hi") }
        print("LIVE \(kind.rawValue) stale session: \(error?.errorDescription ?? "no error")")
        #expect(error?.isSessionMissing == true)
    }

    @Test(arguments: AgentKind.allCases)
    func oneShotAnswers(kind: AgentKind) async throws {
        guard let agent = await agent(kind) else { return }
        let started = ContinuousClock.now
        let answer = try await AgentOneShot(agent: agent).complete(
            "What is 17 + 25? Answer with just the number.", workingDirectory: nil, timeout: .seconds(120)
        )
        print("LIVE \(kind.rawValue) one-shot: \(ContinuousClock.now - started), answer: \(answer)")
        #expect(answer.contains("42"))
    }

    /// A 32x32 single-colour PNG, built by hand because the core has no image framework.
    static func solidPNG(red: UInt8, green: UInt8, blue: UInt8) -> Data {
        let side = 32
        func chunk(_ type: String, _ body: [UInt8]) -> [UInt8] {
            let typed = Array(type.utf8) + body
            return bigEndian(UInt32(body.count)) + typed + bigEndian(crc32(typed))
        }
        func bigEndian(_ value: UInt32) -> [UInt8] { (0..<4).map { UInt8(truncatingIfNeeded: value >> (24 - 8 * $0)) } }
        func crc32(_ bytes: [UInt8]) -> UInt32 {
            var crc: UInt32 = 0xFFFF_FFFF
            for byte in bytes {
                crc ^= UInt32(byte)
                for _ in 0..<8 { crc = (crc >> 1) ^ (crc & 1 == 1 ? 0xEDB8_8320 : 0) }
            }
            return ~crc
        }
        func adler32(_ bytes: [UInt8]) -> UInt32 {
            var a: UInt32 = 1, b: UInt32 = 0
            for byte in bytes { a = (a + UInt32(byte)) % 65521; b = (b + a) % 65521 }
            return (b << 16) | a
        }
        var raw: [UInt8] = []
        for _ in 0..<side { raw.append(0); for _ in 0..<side { raw += [red, green, blue] } }
        // zlib "stored" block: no compression needed for a test image.
        let length = UInt16(raw.count)
        let zlib: [UInt8] = [0x78, 0x01, 0x01, UInt8(length & 0xFF), UInt8(length >> 8), UInt8(~length & 0xFF), UInt8(~length >> 8)]
            + raw + bigEndian(adler32(raw))
        let header = bigEndian(UInt32(side)) + bigEndian(UInt32(side)) + [8, 2, 0, 0, 0]
        return Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A] + chunk("IHDR", header) + chunk("IDAT", zlib) + chunk("IEND", []))
    }
}
#endif
