import Foundation

enum DocumentAssistantError: LocalizedError {
    case noAvailableProvider
    case noVisionCapableProvider
    case noSelectedDocument

    var errorDescription: String? {
        switch self {
        case .noAvailableProvider:
            "No local AI provider is available. Start Ollama or ensure Claude CLI is configured."
        case .noVisionCapableProvider:
            "No vision-capable Ollama model is available. Install a model like Llava or Gemma 3 to explain diagrams."
        case .noSelectedDocument:
            "Import and select a document before asking a question."
        }
    }
}
