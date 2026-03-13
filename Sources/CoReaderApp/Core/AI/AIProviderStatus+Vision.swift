extension AIProviderStatus {
    var preferredVisionModel: String? {
        guard kind == .ollama, isAvailable else {
            return nil
        }

        return models.first(where: Self.isVisionCapableOllamaModel)
    }

    static func isVisionCapableOllamaModel(_ model: String) -> Bool {
        let normalized = model.lowercased()
        let tokens = [
            "vision",
            "llava",
            "bakllava",
            "moondream",
            "minicpm-v",
            "qwen2-vl",
            "qwen2.5-vl",
            "qwen2vl",
            "qwen2.5vl",
            "pixtral",
            "gemma3"
        ]

        return tokens.contains { normalized.contains($0) }
    }
}
