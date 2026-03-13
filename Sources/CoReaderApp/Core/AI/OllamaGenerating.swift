protocol OllamaGenerating: Sendable {
    func generate(model: String, prompt: String) async throws -> String
}
