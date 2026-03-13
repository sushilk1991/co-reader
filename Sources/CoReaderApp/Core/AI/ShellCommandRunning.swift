protocol ShellCommandRunning: Sendable {
    func run(executable: String, arguments: [String]) async throws -> ShellCommandResult
}
