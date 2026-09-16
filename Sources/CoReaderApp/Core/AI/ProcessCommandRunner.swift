import Foundation

/// Runs a child process without blocking a Swift concurrency thread.
///
/// ```
///  await run(command)
///     │
///     ├─ Process.run()  ──▶ child ──▶ stdout/stderr pipes ──▶ readabilityHandler (GCD)
///     │                       ▲                                       │ EOF
///     │   stdin writer (GCD) ─┘                                       ▼
///     │                                                        DispatchGroup ──▶ resume(result)
///     ├─ timeout timer (GCD) ──▶ terminate() ──▶ resume(throwing: timedOut)
///     └─ Task cancelled      ──▶ terminate() ──▶ resume(throwing: CancellationError)
/// ```
/// Whichever path finishes first resumes the continuation; the others become no-ops.
struct ProcessCommandRunner: ShellCommandRunning {
    func run(_ command: ShellCommand) async throws -> ShellCommandResult {
        let session = ProcessSession(command: command)

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                session.start(resuming: continuation)
            }
        } onCancel: {
            session.cancel()
        }
    }
}

private final class ProcessSession: @unchecked Sendable {
    private enum Outcome {
        case running
        case finished
        case timedOut
        case cancelled
    }

    private let command: ShellCommand
    private let process = Process()
    private let stdoutPipe = Pipe()
    private let stderrPipe = Pipe()
    private let stdinPipe: Pipe?
    private let completion = DispatchGroup()
    private let lock = NSLock()
    private var outcome: Outcome = .running
    private var continuation: CheckedContinuation<ShellCommandResult, any Error>?
    private var stdoutData = Data()
    private var stderrData = Data()

    init(command: ShellCommand) {
        self.command = command
        stdinPipe = command.standardInput == nil ? nil : Pipe()
    }

    func start(resuming continuation: CheckedContinuation<ShellCommandResult, any Error>) {
        lock.lock()
        self.continuation = continuation
        let cancelledBeforeStart = outcome == .cancelled
        lock.unlock()

        if cancelledBeforeStart {
            resume(with: .failure(CancellationError()))
            return
        }

        process.executableURL = URL(fileURLWithPath: command.executable)
        process.arguments = command.arguments
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        process.standardInput = stdinPipe ?? FileHandle.nullDevice

        // Three things must finish before the result is complete: stdout EOF,
        // stderr EOF, and the exit status.
        completion.enter()
        completion.enter()
        completion.enter()
        drain(stdoutPipe) { [weak self] chunk in self?.append(chunk, to: \.stdoutData) }
        drain(stderrPipe) { [weak self] chunk in self?.append(chunk, to: \.stderrData) }
        process.terminationHandler = { [completion] _ in
            completion.leave()
        }

        do {
            try process.run()
        } catch {
            resume(with: .failure(error))
            return
        }

        writeStandardInput()
        scheduleTimeout()
        completion.notify(queue: .global()) { [weak self] in
            self?.finish()
        }
    }

    func cancel() {
        lock.lock()
        guard outcome == .running else {
            lock.unlock()
            return
        }
        outcome = .cancelled
        lock.unlock()

        terminateIfRunning()
        resume(with: .failure(CancellationError()))
    }

    private func drain(_ pipe: Pipe, onChunk: @escaping @Sendable (Data) -> Void) {
        let completion = completion
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else {
                handle.readabilityHandler = nil
                completion.leave()
                return
            }

            onChunk(chunk)
        }
    }

    private func append(_ chunk: Data, to keyPath: ReferenceWritableKeyPath<ProcessSession, Data>) {
        lock.lock()
        self[keyPath: keyPath].append(chunk)
        lock.unlock()
    }

    /// Large prompts exceed the pipe buffer, so the write blocks until the child reads.
    /// It runs on a GCD thread after launch; SIGPIPE is disabled so a child that exits
    /// early surfaces as an error instead of killing the app.
    private func writeStandardInput() {
        guard let stdinPipe, let input = command.standardInput else {
            return
        }

        let handle = stdinPipe.fileHandleForWriting
        _ = fcntl(handle.fileDescriptor, F_SETNOSIGPIPE, 1)
        DispatchQueue.global(qos: .userInitiated).async {
            try? handle.write(contentsOf: Data(input.utf8))
            try? handle.close()
        }
    }

    private func scheduleTimeout() {
        let deadline = DispatchTime.now() + .nanoseconds(Int(command.timeout.nanoseconds))
        DispatchQueue.global().asyncAfter(deadline: deadline) { [weak self] in
            self?.expire()
        }
    }

    private func expire() {
        lock.lock()
        guard outcome == .running else {
            lock.unlock()
            return
        }
        outcome = .timedOut
        lock.unlock()

        terminateIfRunning()
        resume(with: .failure(ShellCommandError.timedOut(executable: command.executable, timeout: command.timeout)))
    }

    private func finish() {
        lock.lock()
        guard outcome == .running else {
            lock.unlock()
            return
        }
        outcome = .finished
        let result = ShellCommandResult(
            standardOutput: String(decoding: stdoutData, as: UTF8.self),
            standardError: String(decoding: stderrData, as: UTF8.self),
            exitCode: process.terminationStatus
        )
        lock.unlock()

        resume(with: .success(result))
    }

    private func terminateIfRunning() {
        guard process.isRunning else {
            return
        }

        process.terminate()
    }

    private func resume(with result: Result<ShellCommandResult, any Error>) {
        lock.lock()
        let continuation = continuation
        self.continuation = nil
        lock.unlock()

        continuation?.resume(with: result)
    }
}

private extension Duration {
    var nanoseconds: Int64 {
        components.seconds * 1_000_000_000 + components.attoseconds / 1_000_000_000
    }
}
