import Foundation
import Testing
@testable import CoReaderApp

struct DocumentAssistantTests {
    @Test
    func answerUsesOllamaWhenLocalModelIsAvailable() async throws {
        let ollamaGenerator = StubOllamaGenerator(result: "Ollama answer")
        let claudeGenerator = StubClaudeGenerator(result: "Claude answer")
        let assistant = DocumentAssistant(
            extractor: StubDocumentContextExtractor(
                result: DocumentContext(
                    title: "Distributed Systems",
                    excerpt: "Consensus keeps replicas aligned."
                )
            ),
            ollamaGenerator: ollamaGenerator,
            claudeGenerator: claudeGenerator
        )

        let answer = try await assistant.answer(
            question: "Why does consensus matter?",
            for: ReaderDocument(fileURL: URL(fileURLWithPath: "/tmp/Distributed Systems.pdf")),
            providerStatuses: [
                AIProviderStatus(kind: .ollama, isAvailable: true, detail: "Ollama ready", models: ["llama3.2"]),
                AIProviderStatus(kind: .claudeCLI, isAvailable: true, detail: "Claude ready", models: [])
            ]
        )

        #expect(answer == "Ollama answer")
        #expect(await ollamaGenerator.lastModel == "llama3.2")
        #expect(await ollamaGenerator.lastPrompt?.contains("Why does consensus matter?") == true)
        #expect(await ollamaGenerator.lastPrompt?.contains("Consensus keeps replicas aligned.") == true)
        #expect(await claudeGenerator.callCount == 0)
    }

    @Test
    func answerFallsBackToClaudeWhenOllamaIsUnavailable() async throws {
        let ollamaGenerator = StubOllamaGenerator(result: "unused")
        let claudeGenerator = StubClaudeGenerator(result: "Claude answer")
        let assistant = DocumentAssistant(
            extractor: StubDocumentContextExtractor(
                result: DocumentContext(
                    title: "Async Rust",
                    excerpt: "Pinning keeps futures at stable memory addresses."
                )
            ),
            ollamaGenerator: ollamaGenerator,
            claudeGenerator: claudeGenerator
        )

        let answer = try await assistant.answer(
            question: "Explain pinning simply.",
            for: ReaderDocument(fileURL: URL(fileURLWithPath: "/tmp/Async Rust.pdf")),
            providerStatuses: [
                AIProviderStatus(kind: .ollama, isAvailable: false, detail: "offline", models: []),
                AIProviderStatus(kind: .claudeCLI, isAvailable: true, detail: "Claude ready", models: [])
            ]
        )

        #expect(answer == "Claude answer")
        #expect(await claudeGenerator.lastPrompt?.contains("Explain pinning simply.") == true)
        #expect(await claudeGenerator.lastPrompt?.contains("Pinning keeps futures") == true)
        #expect(await ollamaGenerator.callCount == 0)
    }
}

private struct StubDocumentContextExtractor: DocumentContextExtracting {
    let result: DocumentContext

    func extractContext(for document: ReaderDocument) throws -> DocumentContext {
        result
    }
}

private actor StubOllamaGenerator: OllamaGenerating {
    private(set) var lastModel: String?
    private(set) var lastPrompt: String?
    private(set) var callCount = 0
    let result: String

    init(result: String) {
        self.result = result
    }

    func generate(model: String, prompt: String) async throws -> String {
        lastModel = model
        lastPrompt = prompt
        callCount += 1
        return result
    }
}

private actor StubClaudeGenerator: ClaudeGenerating {
    private(set) var lastPrompt: String?
    private(set) var callCount = 0
    let result: String

    init(result: String) {
        self.result = result
    }

    func generate(prompt: String) async throws -> String {
        lastPrompt = prompt
        callCount += 1
        return result
    }
}
