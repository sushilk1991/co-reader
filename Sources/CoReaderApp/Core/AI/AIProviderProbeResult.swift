enum AIProviderProbeResult: Equatable, Sendable {
    case ready(detail: String, models: [String])
    case unavailable(reason: String)

    static func available(models: [String]) -> Self {
        if models.isEmpty {
            .ready(detail: "Ollama is running, but no local models were found.", models: [])
        } else {
            .ready(detail: "Ollama is ready with \(models.count) model(s).", models: models)
        }
    }

    static func available(version: String) -> Self {
        .ready(detail: "Claude CLI \(version)", models: [])
    }
}
