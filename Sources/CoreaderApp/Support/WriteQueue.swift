import Foundation

/// Runs file writes one at a time per key, in the order they were asked for.
///
/// Notes and book metadata are whole-file rewrites. Two of them racing would each read
/// the same old file and one would win, silently dropping the other's change; and a
/// write still queued when the app quits would be lost. Everything that writes
/// `notes.md` or `book.json` goes through here, and quitting waits for `drain()`.
@MainActor
final class WriteQueue {
    static let shared = WriteQueue()

    private var tails: [String: Task<Void, Never>] = [:]
    private var pending = 0

    /// Queues `work` behind earlier work for the same key.
    func enqueue(_ key: String, _ work: @escaping @Sendable () throws -> Void, onError: (@MainActor (Error) -> Void)? = nil) {
        let previous = tails[key]
        pending += 1
        tails[key] = Task {
            await previous?.value
            do { try await offMain(work) } catch { onError?(error) }
            pending -= 1
        }
    }

    /// Queues `work` and returns its result once its turn has come and gone.
    func perform<T: Sendable>(_ key: String, _ work: @escaping @Sendable () throws -> T) async throws -> T {
        let previous = tails[key]
        pending += 1
        let task = Task { () throws -> T in
            await previous?.value
            defer { pending -= 1 }
            return try await offMain(work)
        }
        tails[key] = Task { _ = try? await task.value }
        return try await task.value
    }

    /// Returns when every queued write has finished.
    func drain() async {
        while pending > 0 {
            for task in Array(tails.values) { await task.value }
        }
    }

    static func notes(_ bookID: String) -> String { "notes:" + bookID }
    static func book(_ bookID: String) -> String { "book:" + bookID }
}
