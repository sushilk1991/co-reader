enum AIProviderKind: String, CaseIterable, Identifiable, Sendable {
    case ollama
    case claudeCLI
    case openAICompatible

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .ollama:
            "Ollama"
        case .claudeCLI:
            "Claude CLI"
        case .openAICompatible:
            "LM Studio"
        }
    }
}
