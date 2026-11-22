import Foundation
import Synchronization

/// Splits a byte stream into lines without assuming chunks end on a newline.
struct AgentLineSplitter {
    /// A single stream-json line can carry a whole tool result; anything past
    /// this is not a line any parser wants, so it is flushed rather than grown.
    static let maximumLineBytes = 64 * 1024 * 1024

    private var pending = Data()

    mutating func feed(_ chunk: Data) -> [String] {
        var lines: [String] = []
        var start = chunk.startIndex
        // Only the new chunk is scanned, so a very long line costs O(n), not O(n²).
        while let newline = chunk[start...].firstIndex(of: 0x0A) {
            pending.append(chunk[start..<newline])
            lines.append(Self.decode(pending))
            pending.removeAll(keepingCapacity: true)
            start = chunk.index(after: newline)
        }
        pending.append(chunk[start...])
        if pending.count > Self.maximumLineBytes {
            lines.append(Self.decode(pending))
            pending.removeAll()
        }
        return lines
    }

    /// The unterminated last line, if any.
    mutating func finish() -> String? {
        guard !pending.isEmpty else { return nil }
        defer { pending.removeAll() }
        return Self.decode(pending)
    }

    private static func decode(_ data: Data) -> String {
        var data = data
        if data.last == 0x0D { data.removeLast() }
        return String(decoding: data, as: UTF8.self)
    }
}

struct AgentProcessSpec: Sendable {
    var executable: URL
    var arguments: [String] = []
    var environment: [String: String] = [:]
    var workingDirectory: URL?
    /// Written to the child's stdin, which is then closed. `nil` connects
    /// stdin to /dev/null, so the child can never wait for a person.
    var stdin: Data?
    /// Fails with `AgentError.timedOut` after this long without output.
    var idleTimeout: Duration = .seconds(300)
    /// Optional cap on the whole run.
    var totalTimeout: Duration?
}

enum AgentProcessOutput: Sendable, Equatable {
    case stdout(String)
    case stderr(String)
    /// Always the last element. Signals are reported as 128 + signal number.
    case exited(Int32)
}

#if os(macOS)

/// A child process in its own process group, read line by line.
///
/// Foundation's `Process` cannot put the child in a new process group, and the
/// agent CLIs spawn helpers (node, sandboxes, MCP servers) that must die with
/// them, so this uses `posix_spawn` directly.
final class AgentProcess: Sendable {
    let output: AsyncThrowingStream<AgentProcessOutput, Error>

    private struct State {
        var pid: pid_t?
        var exitCode: Int32?
        var openPipes = 2
        var finished = false
        /// The child and everything holding its pipes are gone: nothing to kill.
        var endedNaturally = false
        var lastActivity = ContinuousClock.now
        var idleTimeout: Duration
        var deadline: ContinuousClock.Instant?
        var exitExpected = false
    }

    private let state: Mutex<State>
    private let continuation: AsyncThrowingStream<AgentProcessOutput, Error>.Continuation

    static func launch(_ spec: AgentProcessSpec) -> AgentProcess {
        let process = AgentProcess(spec)
        process.start(spec)
        return process
    }

    private init(_ spec: AgentProcessSpec) {
        (output, continuation) = AsyncThrowingStream.makeStream(of: AgentProcessOutput.self)
        state = Mutex(State(
            idleTimeout: spec.idleTimeout,
            deadline: spec.totalTimeout.map { ContinuousClock.now + $0 }
        ))
    }

    /// Kills the whole process group: SIGTERM, then SIGKILL shortly after.
    func terminate() {
        let pid = state.withLock { $0.endedNaturally ? nil : $0.pid }
        guard let pid else { return }
        kill(-pid, SIGTERM)
        DispatchQueue.global().asyncAfter(deadline: .now() + 1.5) {
            // ESRCH once the group is empty, so this is a no-op after a clean exit.
            kill(-pid, SIGKILL)
        }
    }

    /// The answer has arrived; the CLI should now exit on its own. If it does
    /// not within `duration` it is killed and the stream simply ends.
    func expectExit(within duration: Duration) {
        state.withLock {
            $0.exitExpected = true
            $0.idleTimeout = duration
            $0.lastActivity = .now
            $0.deadline = nil
        }
    }

    // MARK: - Launch

    private func start(_ spec: AgentProcessSpec) {
        continuation.onTermination = { [weak self] _ in self?.terminate() }

        let pipes: Spawned
        do {
            pipes = try Self.spawn(spec)
        } catch {
            state.withLock { $0.finished = true; $0.endedNaturally = true }
            continuation.finish(throwing: error)
            return
        }
        state.withLock { $0.pid = pipes.pid }

        if let input = spec.stdin, let fd = pipes.stdin {
            Thread.detachNewThread { Self.writeAll(input, to: fd) }
        }
        Thread.detachNewThread { [self] in read(pipes.stdout) { .stdout($0) } }
        Thread.detachNewThread { [self] in read(pipes.stderr) { .stderr($0) } }
        Thread.detachNewThread { [self] in wait(for: pipes.pid) }
        Task.detached { [self] in await watch() }
    }

    private struct Spawned {
        var pid: pid_t
        var stdin: Int32?
        var stdout: Int32
        var stderr: Int32
    }

    private static func spawn(_ spec: AgentProcessSpec) throws -> Spawned {
        let path = spec.executable.path
        guard FileManager.default.isExecutableFile(atPath: path) else { throw AgentError.notInstalled }

        func makePipe() throws -> (read: Int32, write: Int32) {
            var fds: [Int32] = [0, 0]
            guard pipe(&fds) == 0 else { throw AgentError.failed("Could not start the agent (pipe: \(String(cString: strerror(errno)))).") }
            return (fds[0], fds[1])
        }

        var opened: [Int32] = []
        func closeAll() { opened.forEach { close($0) } }

        do {
            let out = try makePipe(); opened += [out.read, out.write]
            let err = try makePipe(); opened += [err.read, err.write]
            var input: (read: Int32, write: Int32)?
            if spec.stdin != nil {
                let pair = try makePipe(); opened += [pair.read, pair.write]
                // A child that exits before reading its prompt must not SIGPIPE the app.
                _ = fcntl(pair.write, F_SETNOSIGPIPE, 1)
                input = pair
            }

            var actions: posix_spawn_file_actions_t?
            posix_spawn_file_actions_init(&actions)
            defer { posix_spawn_file_actions_destroy(&actions) }
            if let input {
                posix_spawn_file_actions_adddup2(&actions, input.read, 0)
            } else {
                posix_spawn_file_actions_addopen(&actions, 0, "/dev/null", O_RDONLY, 0)
            }
            posix_spawn_file_actions_adddup2(&actions, out.write, 1)
            posix_spawn_file_actions_adddup2(&actions, err.write, 2)
            // CLOEXEC_DEFAULT closes everything not named here, so the child
            // inherits none of the app's descriptors (nor other agents' pipes).
            for fd: Int32 in 0...2 { posix_spawn_file_actions_addinherit_np(&actions, fd) }
            if let directory = spec.workingDirectory {
                posix_spawn_file_actions_addchdir_np(&actions, directory.path)
            }

            var attributes: posix_spawnattr_t?
            posix_spawnattr_init(&attributes)
            defer { posix_spawnattr_destroy(&attributes) }
            var noSignals = sigset_t(), allSignals = sigset_t()
            sigemptyset(&noSignals)
            sigfillset(&allSignals)
            posix_spawnattr_setsigmask(&attributes, &noSignals)
            posix_spawnattr_setsigdefault(&attributes, &allSignals)
            posix_spawnattr_setpgroup(&attributes, 0)
            posix_spawnattr_setflags(&attributes, Int16(
                POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_CLOEXEC_DEFAULT | POSIX_SPAWN_SETSIGMASK | POSIX_SPAWN_SETSIGDEF
            ))

            let argv: [UnsafeMutablePointer<CChar>?] = ([path] + spec.arguments).map { strdup($0) } + [nil]
            let envp: [UnsafeMutablePointer<CChar>?] = spec.environment.map { strdup("\($0.key)=\($0.value)") } + [nil]
            defer { (argv + envp).forEach { free($0) } }

            var pid: pid_t = 0
            let status = posix_spawn(&pid, path, &actions, &attributes, argv, envp)
            guard status == 0 else {
                throw AgentError.failed("Could not start \(spec.executable.lastPathComponent): \(String(cString: strerror(status))).")
            }
            close(out.write); close(err.write)
            if let input { close(input.read) }
            return Spawned(pid: pid, stdin: input?.write, stdout: out.read, stderr: err.read)
        } catch {
            closeAll()
            throw error
        }
    }

    // MARK: - Threads

    private static func writeAll(_ data: Data, to fd: Int32) {
        defer { close(fd) }
        data.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) in
            var offset = 0
            while offset < buffer.count {
                let written = write(fd, buffer.baseAddress! + offset, buffer.count - offset)
                if written > 0 {
                    offset += written
                } else if errno != EINTR {
                    return // EPIPE: the child stopped reading.
                }
            }
        }
    }

    private func read(_ fd: Int32, wrap: (String) -> AgentProcessOutput) {
        var splitter = AgentLineSplitter()
        let capacity = 64 * 1024
        let buffer = UnsafeMutableRawPointer.allocate(byteCount: capacity, alignment: 1)
        defer { buffer.deallocate(); close(fd) }
        while true {
            let count = Darwin.read(fd, buffer, capacity)
            if count > 0 {
                state.withLock { $0.lastActivity = .now }
                for line in splitter.feed(Data(bytes: buffer, count: count)) { continuation.yield(wrap(line)) }
            } else if count == 0 || errno != EINTR {
                break
            }
        }
        if let rest = splitter.finish() { continuation.yield(wrap(rest)) }
        state.withLock { $0.openPipes -= 1 }
        finishIfDone()
    }

    private func wait(for pid: pid_t) {
        var status: Int32 = 0
        while waitpid(pid, &status, 0) == -1 && errno == EINTR {}
        let signal = status & 0x7F
        let code = signal == 0 ? (status >> 8) & 0xFF : 128 + signal
        state.withLock { $0.exitCode = code }
        finishIfDone()

        // A helper that outlives the CLI can hold the pipes open forever.
        // Give buffered output a moment to drain, then stop waiting for EOF.
        for _ in 0..<40 where !state.withLock({ $0.finished }) { usleep(50_000) }
        finishIfDone(force: true)
    }

    private func finishIfDone(force: Bool = false) {
        let code: Int32? = state.withLock { state in
            guard !state.finished, let code = state.exitCode, force || state.openPipes == 0 else { return nil }
            state.finished = true
            state.endedNaturally = state.openPipes == 0
            return code
        }
        guard let code else { return }
        continuation.yield(.exited(code))
        continuation.finish()
    }

    private func watch() async {
        while true {
            let tick: Duration = state.withLock { min(max($0.idleTimeout / 4, .milliseconds(20)), .milliseconds(500)) }
            try? await Task.sleep(for: tick)
            enum Verdict { case keepWaiting, stop, timedOut, quietEnd }
            let verdict: Verdict = state.withLock { state in
                if state.finished { return .stop }
                let now = ContinuousClock.now
                let idle = now - state.lastActivity > state.idleTimeout
                let late = state.deadline.map { now > $0 } ?? false
                guard idle || late else { return .keepWaiting }
                state.finished = true
                return state.exitExpected ? .quietEnd : .timedOut
            }
            switch verdict {
            case .keepWaiting: continue
            case .stop: return
            // Finishing the stream runs `onTermination`, which kills the group.
            case .timedOut: continuation.finish(throwing: AgentError.timedOut); return
            case .quietEnd: continuation.finish(); return
            }
        }
    }
}

extension AgentProcess {
    struct Captured: Sendable {
        var stdout: String
        var stderr: String
        var exitCode: Int32
    }

    /// Runs a short command to completion. Cancelling the task kills it.
    static func capture(_ spec: AgentProcessSpec) async throws -> Captured {
        let process = launch(spec)
        var captured = Captured(stdout: "", stderr: "", exitCode: -1)
        for try await item in process.output {
            switch item {
            case .stdout(let line): captured.stdout += line + "\n"
            case .stderr(let line): captured.stderr += line + "\n"
            case .exited(let code): captured.exitCode = code
            }
        }
        try Task.checkCancellation()
        return captured
    }
}

#endif
