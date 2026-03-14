import Foundation

protocol AIProviderProbing: Sendable {
    func probe() async throws -> AIProviderProbeResult
}

protocol OllamaProbing: AIProviderProbing {}
protocol ClaudeCLIProbing: AIProviderProbing {}

struct AIProviderDiscovery: Sendable {
    let ollamaProbe: OllamaProbing
    let claudeProbe: ClaudeCLIProbing
    let openAIProbe: OpenAICompatibleProbing

    init(
        ollamaProbe: OllamaProbing,
        claudeProbe: ClaudeCLIProbing,
        openAIProbe: OpenAICompatibleProbing = OpenAICompatibleClient()
    ) {
        self.ollamaProbe = ollamaProbe
        self.claudeProbe = claudeProbe
        self.openAIProbe = openAIProbe
    }

    static func live() -> AIProviderDiscovery {
        AIProviderDiscovery(
            ollamaProbe: OllamaClient(),
            claudeProbe: ClaudeCLIProbe(),
            openAIProbe: OpenAICompatibleClient()
        )
    }

    func discoverProviders() async throws -> [AIProviderStatus] {
        async let ollamaStatus = makeStatus(for: .ollama, using: ollamaProbe)
        async let claudeStatus = makeStatus(for: .claudeCLI, using: claudeProbe)
        async let openAIStatus = makeStatus(for: .openAICompatible, using: openAIProbe)
        return try await [ollamaStatus, claudeStatus, openAIStatus]
    }

    private func makeStatus(
        for kind: AIProviderKind,
        using probe: some AIProviderProbing
    ) async throws -> AIProviderStatus {
        do {
            let result = try await probe.probe()
            return status(for: kind, result: result)
        } catch {
            return AIProviderStatus(
                kind: kind,
                isAvailable: false,
                detail: error.localizedDescription,
                models: []
            )
        }
    }

    private func status(for kind: AIProviderKind, result: AIProviderProbeResult) -> AIProviderStatus {
        switch result {
        case let .ready(detail, models):
            AIProviderStatus(kind: kind, isAvailable: true, detail: detail, models: models)
        case let .unavailable(reason):
            AIProviderStatus(kind: kind, isAvailable: false, detail: reason, models: [])
        }
    }
}
