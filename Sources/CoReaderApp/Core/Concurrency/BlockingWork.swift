import Foundation

/// Runs blocking, CPU- or I/O-bound work on a GCD thread so neither the main
/// actor nor the cooperative thread pool is pinned while it runs.
///
/// ```
///   caller task ── await run(work) ──▶ DispatchQueue.global ──▶ work(isCancelled)
///        │                                                          ▲
///        └── Task.cancel() ──▶ flag.cancel() ── polled between steps ┘
/// ```
/// Cancellation is cooperative: `work` receives an `isCancelled` probe and is
/// expected to throw `CancellationError` once it observes `true`.
enum BlockingWork {
    static func run<Output: Sendable>(
        qos: DispatchQoS.QoSClass = .userInitiated,
        _ work: @escaping @Sendable (_ isCancelled: @escaping @Sendable () -> Bool) throws -> Output
    ) async throws -> Output {
        let flag = CancellationFlag()

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global(qos: qos).async {
                    guard !flag.isCancelled else {
                        continuation.resume(throwing: CancellationError())
                        return
                    }

                    continuation.resume(with: Result { try work { flag.isCancelled } })
                }
            }
        } onCancel: {
            flag.cancel()
        }
    }
}

/// Shared between the awaiting task (which sets it) and the GCD worker (which polls it).
private final class CancellationFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    var isCancelled: Bool {
        lock.withLock { cancelled }
    }

    func cancel() {
        lock.withLock { cancelled = true }
    }
}
