import Foundation

/// CLIs that can render a cover. Both end up in Codex's built-in image tool, which runs
/// on the user's ChatGPT sign-in: `yoyo imagegen` wraps it and verifies the file, plain
/// `codex exec` is the fallback for machines without yoyo.
public enum CoverBackend: String, Sendable, CaseIterable {
    case yoyo, codex

    var executableName: String { rawValue }
}

public enum CoverGenerationError: Error, Sendable, Equatable, LocalizedError {
    case backendUnavailable(CoverBackend)
    case timedOut(CoverBackend)
    case failed(CoverBackend, status: Int32, output: String)
    /// The CLI exited cleanly but left no real image at the requested path.
    case noImageProduced(CoverBackend, output: String)

    public var errorDescription: String? {
        switch self {
        case .backendUnavailable(let backend): "\(backend.rawValue) is not installed or not on the PATH."
        case .timedOut(let backend): "\(backend.rawValue) took too long to generate the cover."
        case .failed(let backend, let status, let output):
            "\(backend.rawValue) failed (exit \(status)). \(output.suffix(400))"
        case .noImageProduced(let backend, _): "\(backend.rawValue) finished without producing an image."
        }
    }
}

public struct CoverGenerator: Sendable {
    private let runner: any CoverCommandRunning
    private let locator: any CoverExecutableLocating
    private let timeout: TimeInterval

    public init() {
        self.init(runner: CoverProcessRunner(), locator: CoverExecutableLocator())
    }

    /// Image generation takes one to three minutes when it works; the timeout only has to
    /// catch a hung CLI, so it is generous.
    init(runner: any CoverCommandRunning, locator: any CoverExecutableLocating, timeout: TimeInterval = 20 * 60) {
        self.runner = runner
        self.locator = locator
        self.timeout = timeout
    }

    public func availableBackends() async -> [CoverBackend] {
        var directories = await locator.searchDirectories(includeLoginShell: false)
        var found = CoverBackend.allCases.filter { locator.locate($0.executableName, in: directories) != nil }
        if found.count < CoverBackend.allCases.count {
            // Only pay for a shell start when the usual places came up short.
            directories = await locator.searchDirectories(includeLoginShell: true)
            found = CoverBackend.allCases.filter { locator.locate($0.executableName, in: directories) != nil }
        }
        return found
    }

    /// Generates a cover and returns the image file inside `outputDirectory`.
    /// Cancelling the task kills the CLI.
    public func generate(_ brief: CoverBrief, backend: CoverBackend, outputDirectory: URL) async throws -> URL {
        // The child needs the full PATH too: yoyo itself launches codex.
        let directories = await locator.searchDirectories(includeLoginShell: true)
        guard let executable = locator.locate(backend.executableName, in: directories) else {
            throw CoverGenerationError.backendUnavailable(backend)
        }
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        let stem = "cover-" + UUID().uuidString.lowercased().prefix(8)
        let output = outputDirectory.appendingPathComponent(stem + ".png")

        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = directories.joined(separator: ":")
        let command = CoverCommand(
            executable: executable,
            arguments: Self.arguments(for: backend, prompt: CoverPromptBuilder.prompt(for: brief), output: output),
            environment: environment,
            workingDirectory: outputDirectory,
            timeout: timeout
        )

        let result = try await runner.run(command)
        if result.timedOut { throw CoverGenerationError.timedOut(backend) }
        guard result.status == 0 else {
            throw CoverGenerationError.failed(backend, status: result.status, output: result.output)
        }
        guard let image = Self.producedImage(stem: stem, in: outputDirectory) else {
            throw CoverGenerationError.noImageProduced(backend, output: result.output)
        }
        return image
    }

    // MARK: Command lines

    static func arguments(for backend: CoverBackend, prompt: String, output: URL) -> [String] {
        let size = "\(CoverPromptBuilder.imageWidth)x\(CoverPromptBuilder.imageHeight)"
        switch backend {
        case .yoyo:
            // No --timeout: yoyo's own default is far above ours and our runner kills it.
            return [
                "imagegen", prompt,
                "--out", output.path,
                "--size", size,
                "--quality", "high",
                "--cwd", output.deletingLastPathComponent().path,
                "--caller", "coreader",
                "--quiet",
            ]
        case .codex:
            // workspace-write rooted at the output folder is enough: the image tool saves
            // under $CODEX_HOME/generated_images and the agent copies it into the folder.
            return [
                "--ask-for-approval", "never",
                "exec",
                "--skip-git-repo-check",
                "--ephemeral",
                "--color", "never",
                "--sandbox", "workspace-write",
                "-C", output.deletingLastPathComponent().path,
                codexPrompt(imagePrompt: prompt, output: output, size: size),
            ]
        }
    }

    static func codexPrompt(imagePrompt: String, output: URL, size: String) -> String {
        """
        You are being called as an image-generation worker. Generate one image with your built-in \
        image generation tool (the imagegen skill's image_gen tool; it needs no API key).
        Hard constraints:
        - Do NOT draw the image with code: no PIL, matplotlib, SVG, HTML canvas or scripts. \
        If no real image-generation tool is available, create nothing, say so and exit.
        - Save the single final image as a PNG to exactly this path: \(output.path)
          (the tool saves under $CODEX_HOME/generated_images/; copy that file to the path above).
        - Do not create any other files. After saving, confirm the file exists and report its byte size.

        Image prompt:
        \(imagePrompt)
        Size: \(size) (portrait, 2:3).
        Quality: high.
        """
    }

    // MARK: Result

    /// The file at the requested stem, if it really is an image. The extension is not
    /// trusted: a CLI may save a JPEG or WebP, or leave a text file behind on failure.
    static func producedImage(stem: String, in directory: URL) -> URL? {
        for ext in ["png", "jpg", "jpeg", "webp"] {
            let candidate = directory.appendingPathComponent("\(stem).\(ext)")
            guard let handle = try? FileHandle(forReadingFrom: candidate) else { continue }
            defer { try? handle.close() }
            let head = (try? handle.read(upToCount: 12)) ?? Data()
            let size = (try? FileManager.default.attributesOfItem(atPath: candidate.path)[.size] as? Int) ?? 0
            if size >= 1024, isImage(head) { return candidate }
        }
        return nil
    }

    static func isImage(_ head: Data) -> Bool {
        let bytes = [UInt8](head)
        if bytes.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return true }             // PNG
        if bytes.starts(with: [0xFF, 0xD8, 0xFF]) { return true }                   // JPEG
        if bytes.count >= 12, bytes.starts(with: Array("RIFF".utf8)),
           Array(bytes[8..<12]) == Array("WEBP".utf8) { return true }               // WebP
        return false
    }
}
