import Foundation

protocol OpenAICompatibleProbing: AIProviderProbing {}

struct OpenAICompatibleClient: OpenAICompatibleProbing, OpenAICompatibleGenerating {
    let baseURL: URL
    let httpClient: HTTPDataLoading
    let requestPerformer: HTTPRequestPerforming

    init(
        baseURL: URL = URL(string: "http://127.0.0.1:1234")!,
        httpClient: HTTPDataLoading = URLSessionHTTPClient(),
        requestPerformer: HTTPRequestPerforming = URLSessionRequestPerformer()
    ) {
        self.baseURL = baseURL
        self.httpClient = httpClient
        self.requestPerformer = requestPerformer
    }

    func probe() async throws -> AIProviderProbeResult {
        do {
            let modelsURL = baseURL.appending(path: "/v1/models")
            let (data, response) = try await httpClient.data(from: modelsURL)

            guard let httpResponse = response as? HTTPURLResponse,
                  (200 ..< 300).contains(httpResponse.statusCode) else {
                return .unavailable(reason: "OpenAI-compatible server returned an unexpected status.")
            }

            let models = try decodeModels(from: data)
            return .openAICompatibleAvailable(models: models)
        } catch {
            return .unavailable(reason: "No OpenAI-compatible server at \(baseURL.host() ?? "localhost")")
        }
    }

    func generate(model: String, prompt: String) async throws -> String {
        var request = URLRequest(url: baseURL.appending(path: "/v1/chat/completions"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": "You are Co-Reader, an AI study partner for dense technical documents. Be concise and grounded."],
                ["role": "user", "content": prompt]
            ],
            "stream": false,
            "temperature": 0.3
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await requestPerformer.send(request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200 ..< 300).contains(httpResponse.statusCode) else {
            throw NSError(
                domain: "CoReader.OpenAICompatibleClient",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "OpenAI-compatible generation failed."]
            )
        }

        return try extractContent(from: data)
    }

    private func decodeModels(from data: Data) throws -> [String] {
        let object = try JSONSerialization.jsonObject(with: data)
        guard let payload = object as? [String: Any],
              let models = payload["data"] as? [[String: Any]] else {
            return []
        }
        return models.compactMap { $0["id"] as? String }.sorted()
    }

    private func extractContent(from data: Data) throws -> String {
        let object = try JSONSerialization.jsonObject(with: data)
        guard let payload = object as? [String: Any],
              let choices = payload["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw NSError(
                domain: "CoReader.OpenAICompatibleClient",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Unable to parse chat completion response."]
            )
        }
        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
