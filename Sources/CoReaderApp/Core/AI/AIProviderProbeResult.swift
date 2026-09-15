enum AIProviderProbeResult: Equatable, Sendable {
    case ready(detail: String, models: [String])
    case unavailable(reason: String)

    /// `models` lists chat-capable models only; embedding-only ones are named in the
    /// detail so the user learns why they are not offered.
    static func available(models: [String], skippedEmbeddingModels: [String] = []) -> Self {
        if models.isEmpty, !skippedEmbeddingModels.isEmpty {
            return .ready(
                detail: "Ollama is running, but only embedding models are installed (\(skippedEmbeddingModels.joined(separator: ", "))). Pull a chat model such as llama3.2.",
                models: []
            )
        }

        if models.isEmpty {
            return .ready(detail: "Ollama is running, but no local models were found.", models: [])
        }

        var detail = "Ollama is ready with \(models.count) chat model(s)."
        if !skippedEmbeddingModels.isEmpty {
            detail += " Skipped \(skippedEmbeddingModels.count) embedding-only model(s)."
        }

        return .ready(detail: detail, models: models)
    }

    static func available(version: String) -> Self {
        .ready(detail: "Claude CLI \(version)", models: [])
    }
}
