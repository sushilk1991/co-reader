import Foundation

/// One child-process invocation for cover generation.
struct CoverCommand: Sendable, Equatable {
    var executable: URL
    var arguments: [String]
    var environment: [String: String]
    var workingDirectory: URL
    var timeout: TimeInterval
}

struct CoverCommandResult: Sendable, Equatable {
    var status: Int32
    /// Tail of combined stdout and stderr, for error messages.
    var output: String
    var timedOut: Bool
}

/// Seam for tests: the real runner spawns a process, fakes write a file.
protocol CoverCommandRunning: Sendable {
    func run(_ command: CoverCommand) async throws -> CoverCommandResult
}

/// Runs a child with a hard timeout; cancelling the calling task kills the child.
struct CoverProcessRunner: CoverCommandRunning {
    func run(_ command: CoverCommand) async throws -> CoverCommandResult {
        // Output goes to a file, not a pipe: nothing has to drain it while the child runs,
        // so a chatty child cannot block on a full pipe buffer.
        let logURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("coreader-cover-\(UUID().uuidString).log")
        FileManager.default.createFile(atPath: logURL.path, contents: nil)
        let log = try FileHandle(forWritingTo: logURL)
        defer {
            try? log.close()
            try? FileManager.default.removeItem(at: logURL)
        }

        let process = Process()
        process.executableURL = command.executable
        process.arguments = command.arguments
        process.environment = command.environment
        process.currentDirectoryURL = command.workingDirectory
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = log
        process.standardError = log

        let child = Child(process)
        let status: Int32 = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Int32, Error>) in
                process.terminationHandler = { finished in
                    continuation.resume(returning: finished.terminationStatus)
                }
                do {
                    try child.launch(timeout: command.timeout)
                } catch {
                    // The handler never fires for a process that did not start.
                    process.terminationHandler = nil
                    continuation.resume(throwing: error)
                }
            }
        } onCancel: {
            child.kill()
        }
        try Task.checkCancellation()

        let data = (try? Data(contentsOf: logURL)) ?? Data()
        let text = String(decoding: data.suffix(6000), as: UTF8.self)
        return CoverCommandResult(status: status, output: text, timedOut: child.timedOut)
    }

    /// `Process` is not Sendable; every touch goes through the lock.
    private final class Child: @unchecked Sendable {
        private let process: Process
        private let lock = NSLock()
        private var started = false
        private var cancelled = false
        private var didTimeOut = false

        init(_ process: Process) { self.process = process }

        var timedOut: Bool { lock.withLock { didTimeOut } }

        func launch(timeout: TimeInterval) throws {
            try lock.withLock {
                // Cancelled before it started: do not start at all.
                if cancelled { throw CancellationError() }
                try process.run()
                started = true
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { [self] in
                let expired = lock.withLock { () -> Bool in
                    guard process.isRunning else { return false }
                    didTimeOut = true
                    return true
                }
                if expired { kill() }
            }
        }

        func kill() {
            let pid: Int32? = lock.withLock {
                cancelled = true
                guard started, process.isRunning else { return nil }
                process.terminate()
                return process.processIdentifier
            }
            guard let pid else { return }
            // A child that ignores SIGTERM does not get to outlive the request.
            DispatchQueue.global().asyncAfter(deadline: .now() + 3) { [self] in
                let stillRunning = lock.withLock { process.isRunning }
                if stillRunning { Foundation.kill(pid, SIGKILL) }
            }
        }
    }
}

/// Finds agent CLIs. A GUI app is launched with a bare PATH (`/usr/bin:/bin:...`), not
/// the one a terminal has, so tools in `~/.local/bin` or Homebrew are invisible unless
/// we look there ourselves and, failing that, ask the user's login shell.
protocol CoverExecutableLocating: Sendable {
    /// Directories to search, in order. `includeLoginShell` adds the login shell's PATH,
    /// which costs a shell start.
    func searchDirectories(includeLoginShell: Bool) async -> [String]
}

extension CoverExecutableLocating {
    func locate(_ name: String, in directories: [String]) -> URL? {
        for directory in directories {
            let candidate = URL(fileURLWithPath: directory).appendingPathComponent(name)
            if FileManager.default.isExecutableFile(atPath: candidate.path) { return candidate }
        }
        return nil
    }
}

struct CoverExecutableLocator: CoverExecutableLocating {
    var environment: [String: String] = ProcessInfo.processInfo.environment
    var home: URL = FileManager.default.homeDirectoryForCurrentUser

    func searchDirectories(includeLoginShell: Bool) async -> [String] {
        var directories = (environment["PATH"] ?? "").split(separator: ":").map(String.init)
        directories += [
            home.appendingPathComponent(".local/bin").path,
            "/opt/homebrew/bin",
            "/usr/local/bin",
            home.appendingPathComponent(".cargo/bin").path,
            home.appendingPathComponent(".npm-global/bin").path,
            "/usr/bin",
            "/bin",
        ]
        if includeLoginShell {
            directories += await loginShellPath()
        }
        var seen = Set<String>()
        return directories.filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    private func loginShellPath() async -> [String] {
        let shell = environment["SHELL"].flatMap { $0.isEmpty ? nil : $0 } ?? "/bin/zsh"
        // Interactive as well as login: most people set PATH in .zshrc. Markers fence the
        // value off from whatever the rc files print.
        let command = CoverCommand(
            executable: URL(fileURLWithPath: shell),
            arguments: ["-l", "-i", "-c", "printf '__COREADER_PATH__%s__COREADER_END__' \"$PATH\""],
            environment: environment,
            workingDirectory: home,
            timeout: 8
        )
        guard let result = try? await CoverProcessRunner().run(command),
              let start = result.output.range(of: "__COREADER_PATH__"),
              let end = result.output.range(of: "__COREADER_END__", range: start.upperBound..<result.output.endIndex)
        else { return [] }
        return result.output[start.upperBound..<end.lowerBound].split(separator: ":").map(String.init)
    }
}
