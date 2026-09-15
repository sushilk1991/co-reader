protocol ShellCommandRunning: Sendable {
    func run(_ command: ShellCommand) async throws -> ShellCommandResult
}
