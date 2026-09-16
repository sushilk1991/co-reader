extension AIProviderStatus {
    /// First Ollama model; the probe lists only chat-capable ones (`OllamaModelCatalog`).
    var preferredChatModel: String? {
        guard kind == .ollama, isAvailable else {
            return nil
        }

        return models.first
    }
}

extension [AIProviderStatus] {
    /// Why no provider can answer a text question right now, or nil when one can.
    /// The single owner of that rule: the Claude CLI counts, and so does an
    /// available Ollama with a chat-capable model. Embedding-only Ollama is not
    /// enough. Shared by `DocumentAssistant` and the auto-summary card.
    var textAnswerBlocker: DocumentAssistantError? {
        if contains(where: { $0.kind == .claudeCLI && $0.isAvailable }) {
            return nil
        }

        if contains(where: { $0.preferredChatModel != nil }) {
            return nil
        }

        if contains(where: { $0.kind == .ollama && $0.isAvailable }) {
            return .noChatCapableOllamaModel
        }

        return .noAvailableProvider
    }
}
