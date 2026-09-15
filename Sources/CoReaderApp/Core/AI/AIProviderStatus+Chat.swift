extension AIProviderStatus {
    /// First Ollama model; the probe lists only chat-capable ones (`OllamaModelCatalog`).
    var preferredChatModel: String? {
        guard kind == .ollama, isAvailable else {
            return nil
        }

        return models.first
    }
}
