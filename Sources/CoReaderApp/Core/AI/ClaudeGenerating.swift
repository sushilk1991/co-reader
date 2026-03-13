protocol ClaudeGenerating: Sendable {
    func generate(prompt: String) async throws -> String
}
