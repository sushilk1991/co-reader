import Foundation

enum DocumentAssistantError: LocalizedError {
    case noAvailableProvider
    case noSelectedDocument

    var errorDescription: String? {
        switch self {
        case .noAvailableProvider:
            "No local AI provider is available. Start Ollama or ensure Claude CLI is configured."
        case .noSelectedDocument:
            "Import and select a document before asking a question."
        }
    }
}
