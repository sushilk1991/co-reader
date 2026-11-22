#if os(macOS)
import Foundation
import Testing
@testable import CoreaderKit

@Suite struct AgentDetectorTests {
    /// A directory of fake CLIs: `name: script body`.
    func makeBin(_ scripts: [String: String]) throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("coreader-bin-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for (name, body) in scripts {
            let file = directory.appendingPathComponent(name)
            try "#!/bin/sh\n\(body)\n".write(to: file, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.path)
        }
        return directory
    }

    @Test func findsAgentsInWellKnownDirectoriesAndReadsVersions() async throws {
        let bin = try makeBin([
            "claude": "echo '2.1.330 (Claude Code)'",
            "codex": "echo 'codex-cli 0.170.0'",
        ])
        defer { try? FileManager.default.removeItem(at: bin) }
        let empty = URL(fileURLWithPath: "/nonexistent/bin")
        let agents = await AgentDetector(loginShell: nil, wellKnownDirectories: [empty, bin], probeTimeout: .seconds(10)).detect()
        #expect(agents == [
            DetectedAgent(kind: .claude, executable: bin.appendingPathComponent("claude"), version: "2.1.330"),
            DetectedAgent(kind: .codex, executable: bin.appendingPathComponent("codex"), version: "0.170.0"),
        ])
    }

    @Test func aHangingVersionProbeDoesNotHangDetection() async throws {
        let bin = try makeBin(["agy": "sleep 60"])
        defer { try? FileManager.default.removeItem(at: bin) }
        let started = ContinuousClock.now
        let agents = await AgentDetector(loginShell: nil, wellKnownDirectories: [bin], probeTimeout: .milliseconds(500)).detect()
        #expect(agents == [DetectedAgent(kind: .antigravity, executable: bin.appendingPathComponent("agy"), version: nil)])
        #expect(ContinuousClock.now - started < .seconds(5))
    }

    @Test func asksTheLoginShellForItsPath() async throws {
        let bin = try makeBin(["codex": "echo 'codex-cli 9.9.9'"])
        // Stands in for `$SHELL -ilc /usr/bin/env`, with the noise startup files print.
        let shellDirectory = try makeBin(["fakeshell": "echo 'Welcome back!'; echo 'HOME=/x'; echo 'PATH=/nonexistent:\(bin.path)'"])
        defer {
            try? FileManager.default.removeItem(at: bin)
            try? FileManager.default.removeItem(at: shellDirectory)
        }
        let shell = shellDirectory.appendingPathComponent("fakeshell")
        let agents = await AgentDetector(loginShell: shell, wellKnownDirectories: [], probeTimeout: .seconds(10)).detect()
        #expect(agents.map(\.kind) == [.codex])
        #expect(agents.first?.version == "9.9.9")
        // Learned once, and then used to build the PATH agents run with.
        #expect(AgentEnvironment.cachedShellPath(for: shell)?.last?.path == bin.path)
        #expect(AgentEnvironment.environment(for: URL(fileURLWithPath: "/opt/x/bin/claude"))["PATH"]?.contains(bin.path) == true)
    }

    @Test func aHangingLoginShellFallsBackToWellKnownDirectories() async throws {
        let bin = try makeBin(["claude": "echo 1.0.0", "hang": "sleep 60"])
        defer { try? FileManager.default.removeItem(at: bin) }
        let agents = await AgentDetector(
            loginShell: bin.appendingPathComponent("hang"), wellKnownDirectories: [bin], probeTimeout: .milliseconds(500)
        ).detect()
        #expect(agents.map(\.kind) == [.claude])
    }

    @Test func ignoresDirectoriesAndNonExecutablesNamedLikeAgents() throws {
        let bin = try makeBin([:])
        defer { try? FileManager.default.removeItem(at: bin) }
        try FileManager.default.createDirectory(at: bin.appendingPathComponent("claude"), withIntermediateDirectories: true)
        try "text".write(to: bin.appendingPathComponent("codex"), atomically: true, encoding: .utf8)
        #expect(AgentDetector.locate("claude", in: [bin]) == nil)
        #expect(AgentDetector.locate("codex", in: [bin]) == nil)
    }

    @Test func parsesVersions() {
        #expect(AgentDetector.parseVersion("2.1.330 (Claude Code)") == "2.1.330")
        #expect(AgentDetector.parseVersion("codex-cli 0.170.0\n") == "0.170.0")
        #expect(AgentDetector.parseVersion("1.5.13") == "1.5.13")
        #expect(AgentDetector.parseVersion("warning: x\nagy 2.0.0-beta.1") == "2.0.0-beta.1")
        #expect(AgentDetector.parseVersion("no version here") == nil)
    }

    @Test func parsesThePathOutOfAnEnvironmentListing() {
        let listing = "PATH=/early/noise\nSHELL=/bin/zsh\nPATH=/a/bin:relative:/b c/bin\nMANPATH=/x"
        #expect(AgentDetector.parsePath(fromEnvironmentListing: listing).map(\.path) == ["/a/bin", "/b c/bin"])
        #expect(AgentDetector.parsePath(fromEnvironmentListing: "nothing").isEmpty)
    }

    @Test func theEnvironmentPutsTheCLIsOwnDirectoryFirst() {
        let environment = AgentEnvironment.environment(for: URL(fileURLWithPath: "/opt/tools/bin/claude"))
        let path = environment["PATH"]?.split(separator: ":").map(String.init) ?? []
        #expect(path.first == "/opt/tools/bin")
        #expect(path.contains("/opt/homebrew/bin") && path.contains("/usr/bin"))
        #expect(Set(path).count == path.count)
        #expect(environment["NO_COLOR"] == "1")
    }
}
#endif
