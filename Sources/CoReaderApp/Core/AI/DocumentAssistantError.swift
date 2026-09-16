import Foundation

enum DocumentAssistantError: LocalizedError {
    case noAvailableProvider
    case noChatCapableOllamaModel
    case noVisionCapableProvider
    case noSelectedDocument

    var errorDescription: String? {
        switch self {
        case .noAvailableProvider:
            "No local AI provider is available. Start Ollama or ensure Claude CLI is configured."
        case .noChatCapableOllamaModel:
            "Ollama is running, but no chat-capable model is installed; embedding-only models cannot answer questions. Run `ollama pull llama3.2` or install the Claude CLI."
        case .noVisionCapableProvider:
            "No vision-capable Ollama model is available. Install a model like Llava or Gemma 3 to explain diagrams."
        case .noSelectedDocument:
            "Import and select a document before asking a question."
        }
    }
}
