import AppKit
import CoreaderKit
import Foundation

/// The optional connections around the app: the `coreader` command, the agent skill,
/// and Mastisk. Each is a small, reversible change in the user's home folder.
enum Integrations {
    struct CommandResult: Sendable {
        var status: Int32
        var output: String
    }

    /// Runs a tool with a timeout and no shell.
    static func run(_ executable: URL, _ arguments: [String], timeout: TimeInterval = 20) async -> CommandResult {
        await Task.detached {
            let process = Process()
            process.executableURL = executable
            process.arguments = arguments
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            process.standardInput = FileHandle.nullDevice
            do { try process.run() } catch { return CommandResult(status: -1, output: error.localizedDescription) }
            let deadline = DispatchWorkItem { if process.isRunning { process.terminate() } }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: deadline)
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            deadline.cancel()
            return CommandResult(status: process.terminationStatus, output: String(data: data, encoding: .utf8) ?? "")
        }.value
    }

    static var home: URL { FileManager.default.homeDirectoryForCurrentUser }

    // MARK: Command line tool

    static var bundledCLI: URL? {
        let url = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/coreader")
        return FileManager.default.isExecutableFile(atPath: url.path) ? url : nil
    }

    static var cliLink: URL { home.appendingPathComponent(".local/bin/coreader") }

    static var isCLIInstalled: Bool {
        guard let target = try? FileManager.default.destinationOfSymbolicLink(atPath: cliLink.path) else { return false }
        return FileManager.default.isExecutableFile(atPath: target)
    }

    /// Links `~/.local/bin/coreader` to the copy inside the app, so it updates with the app.
    static func installCLI() throws {
        guard let cli = bundledCLI else { throw Problem("This build does not include the command line tool.") }
        let fm = FileManager.default
        try fm.createDirectory(at: cliLink.deletingLastPathComponent(), withIntermediateDirectories: true)
        if (try? fm.destinationOfSymbolicLink(atPath: cliLink.path)) != nil { try fm.removeItem(at: cliLink) }
        guard !fm.fileExists(atPath: cliLink.path) else { throw Problem("\(cliLink.path) already exists and is not a link Coreader made.") }
        try fm.createSymbolicLink(at: cliLink, withDestinationURL: cli)
    }

    // MARK: Agent skill

    static var bundledSkill: URL? {
        let url = Bundle.main.resourceURL?.appendingPathComponent("skill/coreader")
        return url.flatMap { FileManager.default.fileExists(atPath: $0.appendingPathComponent("SKILL.md").path) ? $0 : nil }
    }

    /// Folders where agent CLIs look for skills, limited to the tools present here.
    static var skillHomes: [URL] {
        [".claude", ".codex", ".agents"].map { home.appendingPathComponent($0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
            .map { $0.appendingPathComponent("skills") }
    }

    static var isSkillInstalled: Bool {
        !skillHomes.isEmpty && skillHomes.allSatisfy { FileManager.default.fileExists(atPath: $0.appendingPathComponent("coreader/SKILL.md").path) }
    }

    static func installSkill() throws {
        guard let skill = bundledSkill else { throw Problem("This build does not include the agent skill.") }
        guard !skillHomes.isEmpty else { throw Problem("No agent folders (~/.claude, ~/.codex, ~/.agents) were found.") }
        for home in skillHomes { try copySkill(from: skill, named: "coreader", into: home) }
    }

    /// Copies a skill folder into a skills directory, replacing an older copy of the same skill.
    static func copySkill(from source: URL, named name: String, into skills: URL) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: skills, withIntermediateDirectories: true)
        let target = skills.appendingPathComponent(name)
        if fm.fileExists(atPath: target.path) || (try? fm.destinationOfSymbolicLink(atPath: target.path)) != nil {
            try fm.removeItem(at: target)
        }
        try fm.copyItem(at: source, to: target)
    }

    // MARK: Mastisk

    enum MastiskState: Equatable {
        case notInstalled
        /// Mastisk is here but lacks the Coreader connector.
        case needsConnector
        case disconnected
        case connected(books: Int)
        case remote
        case unknown(String)
    }

    static var mastiskCLI: URL? {
        let candidates = [home.appendingPathComponent(".local/bin/mastisk"), URL(fileURLWithPath: "/opt/homebrew/bin/mastisk"), URL(fileURLWithPath: "/usr/local/bin/mastisk")]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    static func mastiskState() async -> MastiskState {
        guard let cli = mastiskCLI else { return .notInstalled }
        if ProcessInfo.processInfo.environment["MASTISK_URL"] != nil { return .remote }
        let result = await run(cli, ["coreader", "status", "--json"], timeout: 15)
        if result.status == 2 || result.output.contains("No such command") || result.output.contains("invalid choice") { return .needsConnector }
        guard result.status == 0, let data = result.output.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return result.status == 0 ? .unknown("Unexpected answer from Mastisk.") : .needsConnector
        }
        if json["enabled"] as? Bool == true { return .connected(books: json["books"] as? Int ?? 0) }
        return .disconnected
    }

    static func connectMastisk(_ connect: Bool) async -> MastiskState {
        guard let cli = mastiskCLI else { return .notInstalled }
        let result = await run(cli, ["coreader", connect ? "connect" : "disconnect", "--json"], timeout: 30)
        if result.status != 0 { return .unknown(result.output.trimmingCharacters(in: .whitespacesAndNewlines).prefix(200).description) }
        return await mastiskState()
    }

    struct Problem: LocalizedError {
        var message: String
        init(_ message: String) { self.message = message }
        var errorDescription: String? { message }
    }
}
