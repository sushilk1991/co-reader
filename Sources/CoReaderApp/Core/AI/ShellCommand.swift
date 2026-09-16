import Foundation

/// One child-process invocation. `standardInput` is written to the child's stdin
/// (and stdin is closed afterwards); `timeout` bounds the whole run.
struct ShellCommand: Equatable, Sendable {
    let executable: String
    let arguments: [String]
    let standardInput: String?
    let timeout: Duration
}

enum ShellCommandError: LocalizedError, Equatable {
    case timedOut(executable: String, timeout: Duration)

    var errorDescription: String? {
        switch self {
        case let .timedOut(executable, timeout):
            let name = URL(fileURLWithPath: executable).lastPathComponent
            let seconds = Int(timeout.components.seconds)
            return "\(name) did not finish within \(seconds) seconds."
        }
    }
}
