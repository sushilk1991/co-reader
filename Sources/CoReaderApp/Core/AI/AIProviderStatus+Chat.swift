extension AIProviderStatus {
    /// First chat-capable Ollama model. The probe already drops embedding-only tags;
    /// the name check guards statuses built without it (tests, older cached state).
    var preferredChatModel: String? {
        guard kind == .ollama, isAvailable else {
            return nil
        }

        return models.first { !OllamaModelTag.looksEmbeddingOnly(name: $0) }
    }
}
