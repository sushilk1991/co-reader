import Foundation
import Testing
@testable import CoReaderApp

struct OllamaClientTests {
    /// The tag listing's `capabilities` array is authoritative: embedding-only
    /// models are excluded, local chat models come before cloud ones, and the
    /// order is stable across probes.
    @Test
    func probeListsChatCapableModelsLocalFirst() async throws {
        let payload = """
        {"models":[
          {"name":"nomic-embed-text:latest","details":{"family":"nomic-bert"},"capabilities":["embedding"]},
          {"name":"qwen3-coder:480b-cloud","remote_host":"https://ollama.com","details":{"family":"qwen3"},"capabilities":["completion","tools"]},
          {"name":"llama3.2:latest","details":{"family":"llama"},"capabilities":["completion"]},
          {"name":"all-minilm:latest","details":{"family":"bert"},"capabilities":["embedding"]},
          {"name":"gemma3:4b","details":{"family":"gemma3"},"capabilities":["completion","vision"]}
        ]}
        """
        let client = OllamaClient(httpClient: StubHTTPDataLoader(body: payload))

        let result = try await client.probe()

        guard case let .ready(detail, models) = result else {
            Issue.record("Expected ready, got \(result)")
            return
        }
        #expect(models == ["gemma3:4b", "llama3.2:latest", "qwen3-coder:480b-cloud"])
        #expect(detail.contains("3 chat model(s)"))
        #expect(detail.contains("Skipped 2 embedding-only"))
    }

    /// Older servers omit `capabilities`; fall back to family and name evidence.
    @Test
    func probeFallsBackToNameAndFamilyWhenCapabilitiesAreMissing() async throws {
        let payload = """
        {"models":[
          {"name":"nomic-embed-text:latest","details":{"family":"nomic-bert"}},
          {"name":"mistral:7b","details":{"family":"llama"}},
          {"name":"bge-m3:latest","details":{"family":"bert"}}
        ]}
        """
        let client = OllamaClient(httpClient: StubHTTPDataLoader(body: payload))

        let result = try await client.probe()

        #expect(result == .available(models: ["mistral:7b"], skippedEmbeddingModels: ["bge-m3:latest", "nomic-embed-text:latest"]))
    }

    @Test
    func probeExplainsWhenOnlyEmbeddingModelsAreInstalled() async throws {
        let payload = """
        {"models":[{"name":"nomic-embed-text:latest","capabilities":["embedding"]}]}
        """
        let client = OllamaClient(httpClient: StubHTTPDataLoader(body: payload))

        let result = try await client.probe()

        guard case let .ready(detail, models) = result else {
            Issue.record("Expected ready, got \(result)")
            return
        }
        #expect(models.isEmpty)
        #expect(detail.contains("only embedding models"))
        #expect(detail.contains("nomic-embed-text:latest"))
    }

    @Test
    func preferredChatModelSkipsEmbeddingNamesInStatus() {
        let status = AIProviderStatus(
            kind: .ollama,
            isAvailable: true,
            detail: "ready",
            models: ["all-minilm:latest", "llama3.2", "nomic-embed-text:latest"]
        )

        #expect(status.preferredChatModel == "llama3.2")
        #expect(AIProviderStatus(kind: .ollama, isAvailable: true, detail: "ready", models: ["all-minilm:latest"]).preferredChatModel == nil)
        #expect(AIProviderStatus(kind: .claudeCLI, isAvailable: true, detail: "ready", models: ["llama3.2"]).preferredChatModel == nil)
    }
}

private struct StubHTTPDataLoader: HTTPDataLoading {
    let body: String

    func data(from url: URL) async throws -> (Data, URLResponse) {
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
        return (Data(body.utf8), response)
    }
}
