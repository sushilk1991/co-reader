import Foundation

struct OllamaClient: OllamaProbing {
    let baseURL: URL
    let httpClient: HTTPDataLoading

    init(
        baseURL: URL = URL(string: "http://127.0.0.1:11434")!,
        httpClient: HTTPDataLoading = URLSessionHTTPClient()
    ) {
        self.baseURL = baseURL
        self.httpClient = httpClient
    }

    func probe() async throws -> AIProviderProbeResult {
        do {
            let tagsURL = baseURL.appending(path: "/api/tags")
            let (data, response) = try await httpClient.data(from: tagsURL)

            guard let httpResponse = response as? HTTPURLResponse,
                  (200 ..< 300).contains(httpResponse.statusCode) else {
                return .unavailable(reason: "Ollama responded with an unexpected status.")
            }

            let tags = try OllamaModelCatalog.decodeTags(from: data)
            return .available(
                models: OllamaModelCatalog.chatModelNames(in: tags),
                skippedEmbeddingModels: OllamaModelCatalog.skippedModelNames(in: tags)
            )
        } catch {
            return .unavailable(reason: "Ollama server did not respond")
        }
    }
}
