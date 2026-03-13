struct ShellCommandResult: Sendable {
    let standardOutput: String
    let standardError: String
    let exitCode: Int32
}
