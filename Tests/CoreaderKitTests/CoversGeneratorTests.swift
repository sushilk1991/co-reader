import Foundation
import Testing
@testable import CoreaderKit

private let attention = CoverBrief(
    title: "Attention Is All You Need",
    authors: ["Ashish Vaswani", "Noam Shazeer", "Niki Parmar"],
    summary: "A sequence model built only from attention, with no recurrence or convolution.",
    kind: .paper
)

@Test func coverPromptIsDeterministicAndCarriesTheRules() {
    let prompt = CoverPromptBuilder.prompt(for: attention)
    #expect(prompt == CoverPromptBuilder.prompt(for: attention))
    #expect(prompt.contains("\"Attention Is All You Need\""))
    #expect(prompt.contains("\"Ashish Vaswani et al.\""))
    #expect(prompt.contains("2:3"))
    #expect(prompt.contains("No other text"))
    #expect(prompt.contains("no logo"))
    #expect(prompt.contains("Do not show a physical book"))
    #expect(prompt.contains("with no recurrence or convolution"))
    let palette = CoverPalette.palette(for: attention)
    #expect(prompt.contains(palette.ground))
    #expect(prompt.contains(palette.accent))
}

@Test func coverPaletteFollowsTheTitleOnly() {
    var other = attention
    other.summary = "Something else entirely"
    other.authors = []
    #expect(CoverPalette.palette(for: other) == CoverPalette.palette(for: attention))

    let titles = (0..<60).map { "Title number \($0)" }
    let used = Set(titles.map { CoverPalette.palette(for: CoverBrief(title: $0)).name })
    #expect(used.count >= CoverPalette.all.count - 2)
}

@Test func coverMotifFollowsTheSubjectWhenItCan() {
    let fourier = CoverBrief(title: "The Fourier Transform and Its Applications", summary: "Signals as sums of frequencies.")
    #expect(CoverMotif.hits(in: fourier).max { $0.value < $1.value }?.key == .waveInterference)
    #expect(CoverMotif.hits(in: attention).keys.contains(.network))
    // "sun" inside "misunderstood" is not a hint.
    #expect(CoverMotif.hits(in: CoverBrief(title: "Misunderstood")).isEmpty)
}

@Test func coversInOneFieldDoNotAllLookAlike() {
    // Every one of these matches the "network" keywords; the shelf must still vary.
    let papers = ["Attention Is All You Need", "Language Models are Few-Shot Learners", "Scaling Laws for Neural Language Models",
                  "BERT: Pre-training of Deep Bidirectional Transformers", "LLaMA: Open and Efficient Foundation Language Models",
                  "RoFormer: Enhanced Transformer with Rotary Position Embedding", "Training Compute-Optimal Large Language Models",
                  "Deep Learning", "Graph Neural Networks", "Neural Machine Translation", "Transformer Circuits", "Network Science"]
    let motifs = papers.map { CoverMotif.motif(for: CoverBrief(title: $0)) }
    #expect(Set(motifs).count >= 4)
    #expect(motifs.filter { $0 == .network }.count <= papers.count * 2 / 3)
}

@Test func aNewVariantChangesTheCover() {
    var seen = Set<String>()
    for variant in 0..<6 {
        var brief = attention
        brief.variant = variant
        seen.insert(CoverPalette.palette(for: brief).name + "/" + CoverMotif.motif(for: brief).rawValue)
        #expect(ProceduralCover.svg(for: brief) == ProceduralCover.svg(for: brief))
    }
    #expect(seen.count >= 4)
}

@Test func coverBriefShortensLongTitlesAndAuthorLists() {
    let long = CoverBrief(
        title: "  Deep  Residual Learning: a very long subtitle that goes on and on about image recognition at scale  ",
        authors: ["Kaiming He", "Jian Sun"]
    )
    #expect(long.displayTitle == "Deep Residual Learning")
    #expect(long.authorLine == "Kaiming He & Jian Sun")
    #expect(CoverBrief(title: "Short: kept whole").displayTitle == "Short: kept whole")
    #expect(CoverBrief(title: "   ").displayTitle == "Untitled")
    #expect(CoverBrief(title: "x").authorLine == nil)
    let quoted = CoverPromptBuilder.prompt(for: CoverBrief(title: "The \"Real\" Thing"))
    #expect(quoted.contains("\"The 'Real' Thing\""))
}

// MARK: Generator with fakes

private struct FakeLocator: CoverExecutableLocating {
    var directory: URL
    func searchDirectories(includeLoginShell: Bool) async -> [String] { [directory.path] }
}

private final class FakeRunner: CoverCommandRunning, @unchecked Sendable {
    enum Behaviour { case writePNG, writeText, writeNothing, fail, timeOut }
    let behaviour: Behaviour
    private let lock = NSLock()
    private var recorded: [CoverCommand] = []
    var commands: [CoverCommand] { lock.withLock { recorded } }

    init(_ behaviour: Behaviour) { self.behaviour = behaviour }

    func run(_ command: CoverCommand) async throws -> CoverCommandResult {
        lock.withLock { recorded.append(command) }
        // Both backends name the output path: after --out (yoyo) or inside the prompt (codex).
        let all = command.arguments.joined(separator: "\n")
        let match = all.firstMatch(of: /(\/[^\n]*cover-[0-9a-f]{8}\.png)/)
        let path = match.map { String($0.1) } ?? ""
        switch behaviour {
        case .writePNG:
            var png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
            png.append(Data(count: 4096))
            try png.write(to: URL(fileURLWithPath: path))
        case .writeText:
            try Data(String(repeating: "not an image ", count: 400).utf8).write(to: URL(fileURLWithPath: path))
        case .writeNothing: break
        case .fail: return CoverCommandResult(status: 3, output: "boom", timedOut: false)
        case .timeOut: return CoverCommandResult(status: 15, output: "", timedOut: true)
        }
        return CoverCommandResult(status: 0, output: "ok", timedOut: false)
    }
}

/// A folder with empty executables named like the backends.
private func fakeBin(_ names: [String]) throws -> URL {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("coreader-bin-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    for name in names {
        let file = dir.appendingPathComponent(name)
        try Data("#!/bin/sh\n".utf8).write(to: file)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.path)
    }
    return dir
}

@Test func coverGeneratorReportsOnlyInstalledBackends() async throws {
    let bin = try fakeBin(["codex"])
    defer { try? FileManager.default.removeItem(at: bin) }
    let generator = CoverGenerator(runner: FakeRunner(.writePNG), locator: FakeLocator(directory: bin))
    #expect(await generator.availableBackends() == [.codex])
    let out = bin.appendingPathComponent("out")
    await #expect(throws: CoverGenerationError.backendUnavailable(.yoyo)) {
        _ = try await generator.generate(attention, backend: .yoyo, outputDirectory: out)
    }
}

@Test func coverGeneratorBuildsTheYoyoCommand() async throws {
    let bin = try fakeBin(["yoyo", "codex"])
    defer { try? FileManager.default.removeItem(at: bin) }
    let runner = FakeRunner(.writePNG)
    let generator = CoverGenerator(runner: runner, locator: FakeLocator(directory: bin))
    let out = bin.appendingPathComponent("out")
    let image = try await generator.generate(attention, backend: .yoyo, outputDirectory: out)

    #expect(image.deletingLastPathComponent().standardizedFileURL == out.standardizedFileURL)
    #expect(image.pathExtension == "png")
    let command = try #require(runner.commands.first)
    #expect(command.executable.lastPathComponent == "yoyo")
    #expect(command.arguments[0] == "imagegen")
    #expect(command.arguments[1] == CoverPromptBuilder.prompt(for: attention))
    #expect(command.arguments.contains("1024x1536"))
    #expect(command.arguments.contains(image.path))
    #expect(!command.arguments.contains("--timeout"))
    #expect(command.environment["PATH"] == bin.path)
    #expect(command.timeout >= 600)
}

@Test func coverGeneratorBuildsTheCodexCommand() async throws {
    let bin = try fakeBin(["yoyo", "codex"])
    defer { try? FileManager.default.removeItem(at: bin) }
    let runner = FakeRunner(.writePNG)
    let generator = CoverGenerator(runner: runner, locator: FakeLocator(directory: bin))
    let out = bin.appendingPathComponent("out")
    let image = try await generator.generate(attention, backend: .codex, outputDirectory: out)

    let command = try #require(runner.commands.first)
    #expect(command.executable.lastPathComponent == "codex")
    #expect(command.arguments.contains("exec"))
    #expect(command.arguments.contains("workspace-write"))
    let prompt = try #require(command.arguments.last)
    #expect(prompt.contains(image.path))
    #expect(prompt.contains(CoverPromptBuilder.prompt(for: attention)))
    #expect(prompt.contains("1024x1536"))
}

@Test func coverGeneratorRejectsFailuresAndFakeImages() async throws {
    let bin = try fakeBin(["yoyo", "codex"])
    defer { try? FileManager.default.removeItem(at: bin) }
    let out = bin.appendingPathComponent("out")
    func run(_ behaviour: FakeRunner.Behaviour) async throws -> URL {
        try await CoverGenerator(runner: FakeRunner(behaviour), locator: FakeLocator(directory: bin))
            .generate(attention, backend: .yoyo, outputDirectory: out)
    }
    await #expect(throws: CoverGenerationError.failed(.yoyo, status: 3, output: "boom")) { _ = try await run(.fail) }
    await #expect(throws: CoverGenerationError.timedOut(.yoyo)) { _ = try await run(.timeOut) }
    await #expect(throws: CoverGenerationError.noImageProduced(.yoyo, output: "ok")) { _ = try await run(.writeNothing) }
    await #expect(throws: CoverGenerationError.noImageProduced(.yoyo, output: "ok")) { _ = try await run(.writeText) }
}

// MARK: Real process runner (local shell only, no agent CLI)

private func shell(_ script: String, timeout: TimeInterval) -> CoverCommand {
    CoverCommand(
        executable: URL(fileURLWithPath: "/bin/sh"),
        arguments: ["-c", script],
        environment: ["PATH": "/usr/bin:/bin"],
        workingDirectory: FileManager.default.temporaryDirectory,
        timeout: timeout
    )
}

@Test func coverProcessRunnerCapturesOutputAndStatus() async throws {
    let result = try await CoverProcessRunner().run(shell("echo out; echo err 1>&2; exit 4", timeout: 10))
    #expect(result.status == 4)
    #expect(result.output.contains("out"))
    #expect(result.output.contains("err"))
    #expect(!result.timedOut)
}

@Test func coverProcessRunnerKillsOnTimeout() async throws {
    let started = Date()
    let result = try await CoverProcessRunner().run(shell("sleep 30", timeout: 0.3))
    #expect(result.timedOut)
    #expect(Date().timeIntervalSince(started) < 10)
}

@Test func coverProcessRunnerKillsOnCancel() async throws {
    let marker = FileManager.default.temporaryDirectory.appendingPathComponent("coreader-cancel-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: marker) }
    let task = Task {
        try await CoverProcessRunner().run(shell("sleep 2; touch '\(marker.path)'", timeout: 30))
    }
    try await Task.sleep(for: .milliseconds(300))
    task.cancel()
    await #expect(throws: CancellationError.self) { _ = try await task.value }
    try await Task.sleep(for: .milliseconds(2500))
    #expect(!FileManager.default.fileExists(atPath: marker.path))
}

@Test func coverLocatorLooksBeyondTheProcessPath() async {
    let home = URL(fileURLWithPath: "/Users/someone")
    let locator = CoverExecutableLocator(environment: ["PATH": "/usr/bin:/bin"], home: home)
    let directories = await locator.searchDirectories(includeLoginShell: false)
    #expect(directories.prefix(2) == ["/usr/bin", "/bin"])
    #expect(directories.contains("/Users/someone/.local/bin"))
    #expect(directories.contains("/opt/homebrew/bin"))
    #expect(directories.contains("/usr/local/bin"))
    #expect(Set(directories).count == directories.count)
}

// MARK: Live generation (opt-in; calls the real CLI and takes minutes)

/// `COREADER_LIVE_COVER=yoyo|codex COREADER_LIVE_COVER_OUT=/dir swift test --filter liveCoverGeneration`
@Test(.enabled(if: ProcessInfo.processInfo.environment["COREADER_LIVE_COVER"] != nil))
func liveCoverGeneration() async throws {
    let env = ProcessInfo.processInfo.environment
    let backend = try #require(CoverBackend(rawValue: env["COREADER_LIVE_COVER"] ?? ""))
    let out = URL(fileURLWithPath: env["COREADER_LIVE_COVER_OUT"] ?? NSTemporaryDirectory())
    let brief = CoverBrief(
        title: env["COREADER_LIVE_COVER_TITLE"] ?? attention.title,
        authors: (env["COREADER_LIVE_COVER_AUTHORS"]?.components(separatedBy: ";")) ?? attention.authors,
        summary: env["COREADER_LIVE_COVER_SUMMARY"] ?? attention.summary,
        kind: .paper
    )
    let generator = CoverGenerator()
    #expect(await generator.availableBackends().contains(backend))
    let image = try await generator.generate(brief, backend: backend, outputDirectory: out)
    print("COVER_IMAGE=\(image.path)")
}

@Test func coverPromptAsksForAnIdeaAndVariesItsArtDirection() {
    let papers = [
        "Attention Is All You Need", "Switch Transformers", "Textbooks Are All You Need", "FlashAttention",
        "The Platonic Representation Hypothesis", "Scaling Laws for Neural Language Models", "Outrageously Large Neural Networks",
        "Language Models are Few-Shot Learners", "ReAct: Synergizing Reasoning and Acting in Language Models",
        "RoFormer: Enhanced Transformer with Rotary Position Embedding", "Training Compute-Optimal Large Language Models",
        "LLaMA: Open and Efficient Foundation Language Models", "Sparse Upcycling", "PaLM: Scaling Language Modeling with Pathways",
        "Chain-of-Thought Prompting Elicits Reasoning in Large Language Models", "Retrieval-Augmented Generation for Knowledge-Intensive NLP Tasks",
        "Training language models to follow instructions with human feedback",
    ].map { CoverBrief(title: $0, kind: .paper) }
    // One field, one shelf: the covers must not share a recipe.
    #expect(Set(papers.map { CoverDirection.direction(for: $0) }).count >= 7)
    #expect(Set(papers.map { CoverLayout.layout(for: $0) }).count >= 4)
    let looks = papers.map { "\(CoverDirection.direction(for: $0))/\(CoverLayout.layout(for: $0))/\(CoverPalette.palette(for: $0).name)" }
    #expect(Set(looks).count >= papers.count - 1)

    for brief in papers {
        let prompt = CoverPromptBuilder.prompt(for: brief)
        #expect(prompt.contains("Concept first"))
        #expect(prompt.contains(CoverDirection.direction(for: brief).artwork))
    }
    var again = papers[0]
    again.variant = 1
    #expect(CoverPromptBuilder.prompt(for: again) != CoverPromptBuilder.prompt(for: papers[0]))
}
