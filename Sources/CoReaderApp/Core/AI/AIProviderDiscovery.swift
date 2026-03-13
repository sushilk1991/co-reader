import Foundation

protocol AIProviderProbing: Sendable {
    func probe() async throws -> AIProviderProbeResult
}

protocol OllamaProbing: AIProviderProbing {}
protocol ClaudeCLIProbing: AIProviderProbing {}

struct AIProviderDiscovery: Sendable {
    let ollamaProbe: OllamaProbing
    let claudeProbe: ClaudeCLIProbing

    init(ollamaProbe: OllamaProbing, claudeProbe: ClaudeCLIProbing) {
        self.ollamaProbe = ollamaProbe
        self.claudeProbe = claudeProbe
    }

    static func live() -> AIProviderDiscovery {
        AIProviderDiscovery(
            ollamaProbe: OllamaClient(),
            claudeProbe: ClaudeCLIProbe()
        )
    }

    func discoverProviders() async throws -> [AIProviderStatus] {
        async let ollamaStatus = makeStatus(for: .ollama, using: ollamaProbe)
        async let claudeStatus = makeStatus(for: .claudeCLI, using: claudeProbe)
        return try await [ollamaStatus, claudeStatus]
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
