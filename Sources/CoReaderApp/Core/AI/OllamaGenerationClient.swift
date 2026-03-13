import Foundation

struct OllamaGenerationClient: OllamaGenerating {
    let baseURL: URL
    let requestPerformer: HTTPRequestPerforming

    init(
        baseURL: URL = URL(string: "http://127.0.0.1:11434")!,
        requestPerformer: HTTPRequestPerforming = URLSessionRequestPerformer()
    ) {
        self.baseURL = baseURL
        self.requestPerformer = requestPerformer
    }

    func generate(model: String, prompt: String) async throws -> String {
        var request = URLRequest(url: baseURL.appending(path: "/api/generate"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            OllamaGenerationRequest(model: model, prompt: prompt, stream: false)
        )

        let (data, response) = try await requestPerformer.send(request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200 ..< 300).contains(httpResponse.statusCode) else {
            throw NSError(
                domain: "CoReader.OllamaGenerationClient",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Ollama generation failed."]
            )
        }

        let payload = try JSONDecoder().decode(OllamaGenerationResponse.self, from: data)
        return payload.response.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct OllamaGenerationRequest: Encodable {
    let model: String
    let prompt: String
    let stream: Bool
}

private struct OllamaGenerationResponse: Decodable {
    let response: String
}
