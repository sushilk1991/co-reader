enum AIProviderKind: String, CaseIterable, Identifiable, Sendable {
    case ollama
    case claudeCLI

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .ollama:
            "Ollama"
        case .claudeCLI:
            "Claude CLI"
        }
    }
}
