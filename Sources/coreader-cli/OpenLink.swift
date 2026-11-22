import CoreaderKit
import Foundation

/// Hands a `coreader://` link to Launch Services with `-g`, so the app opens the place
/// without coming to the front. Bounded: a stuck `open` is killed after ten seconds.
@Sendable func openInBackground(_ url: URL) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
    process.arguments = ["-g", url.absoluteString]
    let errors = Pipe()
    process.standardError = errors
    process.standardOutput = FileHandle.nullDevice
    let finished = DispatchSemaphore(value: 0)
    process.terminationHandler = { _ in finished.signal() }
    try process.run()
    guard finished.wait(timeout: .now() + 10) == .success else {
        process.terminate()
        throw CoreaderCommand.Failure("Timed out opening \(url.absoluteString).")
    }
    guard process.terminationStatus == 0 else {
        let detail = String(decoding: errors.fileHandleForReading.availableData, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        throw CoreaderCommand.Failure(
            "Could not open \(url.absoluteString). Is the Coreader app installed?" + (detail.isEmpty ? "" : "\n\(detail)"))
    }
}
