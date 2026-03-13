import Foundation

protocol OllamaGenerating: Sendable {
    func generate(model: String, prompt: String, imageData: Data?) async throws -> String
}
