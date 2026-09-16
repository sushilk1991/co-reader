import Foundation

/// One entry from Ollama's `/api/tags` listing, reduced to what model selection needs.
struct OllamaModelTag: Equatable, Sendable {
    let name: String
    /// As reported by the server, e.g. `["completion", "vision"]` or `["embedding"]`.
    /// Empty when the server predates the field; the name heuristic applies then.
    let capabilities: [String]
    let family: String?

    static let completionCapability = "completion"
    private static let embeddingFamilies: Set<String> = ["bert", "nomic-bert"]
    private static let embeddingNameTokens = ["embed", "minilm", "bge"]

    /// Whether this model can answer a prompt. Embedding-only models accept
    /// `/api/generate` calls but return nothing useful.
    var supportsChat: Bool {
        if !capabilities.isEmpty {
            return capabilities.contains(Self.completionCapability)
        }

        return !Self.looksEmbeddingOnly(name: name, family: family)
    }

    static func looksEmbeddingOnly(name: String, family: String? = nil) -> Bool {
        if let family, embeddingFamilies.contains(family.lowercased()) {
            return true
        }

        let normalized = name.lowercased()
        return embeddingNameTokens.contains { normalized.contains($0) }
    }
}

enum OllamaModelCatalog {
    static func decodeTags(from data: Data) throws -> [OllamaModelTag] {
        let object = try JSONSerialization.jsonObject(with: data)
        guard let payload = object as? [String: Any],
              let models = payload["models"] as? [[String: Any]] else {
            return []
        }

        return models.compactMap { entry in
            guard let name = entry["name"] as? String else {
                return nil
            }

            let details = entry["details"] as? [String: Any]
            return OllamaModelTag(
                name: name,
                capabilities: entry["capabilities"] as? [String] ?? [],
                family: details?["family"] as? String
            )
        }
    }

    /// Chat-capable names, sorted so the pick is deterministic across probes.
    static func chatModelNames(in tags: [OllamaModelTag]) -> [String] {
        tags.filter(\.supportsChat).map(\.name).sorted()
    }

    static func skippedModelNames(in tags: [OllamaModelTag]) -> [String] {
        tags.filter { !$0.supportsChat }.map(\.name).sorted()
    }
}
