import Foundation
import Testing
@testable import CoReaderApp

struct AIProviderDiscoveryTests {
    @Test
    func discoveryReportsRunningOllamaAndClaude() async throws {
        let discovery = AIProviderDiscovery(
            ollamaProbe: StubOllamaProbe(
                result: .available(models: ["llama3.2", "qwen2.5-coder"])
            ),
            claudeProbe: StubClaudeCLIProbe(
                result: .available(version: "1.2.3")
            )
        )

        let providers = try await discovery.discoverProviders()

        #expect(providers.count == 2)
        #expect(providers.first(where: { $0.kind == .ollama })?.isAvailable == true)
        #expect(providers.first(where: { $0.kind == .ollama })?.models == ["llama3.2", "qwen2.5-coder"])
        #expect(providers.first(where: { $0.kind == .claudeCLI })?.detail == "Claude CLI 1.2.3")
    }

    @Test
    func discoveryMarksProviderUnavailableWhenProbeFails() async throws {
        let discovery = AIProviderDiscovery(
            ollamaProbe: StubOllamaProbe(
                result: .unavailable(reason: "Ollama server did not respond")
            ),
            claudeProbe: StubClaudeCLIProbe(
                result: .unavailable(reason: "claude not found on PATH")
            )
        )

        let providers = try await discovery.discoverProviders()

        #expect(providers.count == 2)
        #expect(providers.first(where: { $0.kind == .ollama })?.isAvailable == false)
        #expect(providers.first(where: { $0.kind == .ollama })?.detail == "Ollama server did not respond")
        #expect(providers.first(where: { $0.kind == .claudeCLI })?.detail == "claude not found on PATH")
    }
}

private struct StubOllamaProbe: OllamaProbing {
    let result: AIProviderProbeResult

    func probe() async throws -> AIProviderProbeResult {
        result
    }
}

private struct StubClaudeCLIProbe: ClaudeCLIProbing {
    let result: AIProviderProbeResult

    func probe() async throws -> AIProviderProbeResult {
        result
    }
}
