struct AIProviderStatus: Equatable, Identifiable, Sendable {
    let kind: AIProviderKind
    let isAvailable: Bool
    let detail: String
    let models: [String]

    var id: AIProviderKind { kind }
}
