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
            ],
            scope: .focus
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
            ],
            scope: .focus
        )

        #expect(answer == "Claude answer")
        #expect(await claudeGenerator.lastPrompt?.contains("Explain pinning simply.") == true)
        #expect(await claudeGenerator.lastPrompt?.contains("Pinning keeps futures") == true)
        #expect(await ollamaGenerator.callCount == 0)
    }

    /// The probe already filters the listing to chat-capable models; the assistant
    /// generates with the first one it is handed.
    @Test
    func answerUsesFirstListedChatModel() async throws {
        let ollamaGenerator = StubOllamaGenerator(result: "Ollama answer")
        let assistant = DocumentAssistant(
            extractor: StubDocumentContextExtractor(
                result: DocumentContext(title: "Distributed Systems", excerpt: "Consensus keeps replicas aligned.")
            ),
            ollamaGenerator: ollamaGenerator,
            claudeGenerator: StubClaudeGenerator(result: "unused")
        )

        let answer = try await assistant.answer(
            question: "Why does consensus matter?",
            for: ReaderDocument(fileURL: URL(fileURLWithPath: "/tmp/Distributed Systems.pdf")),
            providerStatuses: [
                AIProviderStatus(
                    kind: .ollama,
                    isAvailable: true,
                    detail: "1 chat model(s). Skipped 2 embedding-only: all-minilm:latest, nomic-embed-text:latest",
                    models: ["llama3.2"]
                )
            ],
            scope: .focus
        )

        #expect(answer == "Ollama answer")
        #expect(await ollamaGenerator.lastModel == "llama3.2")
    }

    @Test
    func answerPassesSelectionAndReadingPositionToExtractor() async throws {
        let extractor = RecordingDocumentContextExtractor(
            result: DocumentContext(
                title: "Transformers",
                excerpt: "Selection Focus:\nmulti-head attention\n\n[Page 13]\nMore details."
            )
        )
        let assistant = DocumentAssistant(
            extractor: extractor,
            ollamaGenerator: StubOllamaGenerator(result: "Ollama answer"),
            claudeGenerator: StubClaudeGenerator(result: "Claude answer")
        )
        let selection = DocumentSelection(
            text: "multi-head attention",
            pageIndex: 12,
            surroundingText: "This page describes why attention scales better than recurrence."
        )

        _ = try await assistant.answer(
            question: "Summarize this section",
            for: ReaderDocument(fileURL: URL(fileURLWithPath: "/tmp/Transformers.pdf")),
            providerStatuses: [
                AIProviderStatus(kind: .ollama, isAvailable: true, detail: "ready", models: ["llama3.2"])
            ],
            scope: .document,
            selection: selection,
            currentPageIndex: 12,
            visiblePageIndexes: [12, 13]
        )

        let recordedCall = extractor.lastCall
        #expect(recordedCall?.question == "Summarize this section")
        #expect(recordedCall?.scope == .document)
        #expect(recordedCall?.selection == selection)
        #expect(recordedCall?.currentPageIndex == 12)
        #expect(recordedCall?.visiblePageIndexes == [12, 13])
    }

    @Test
    func answerUsesVisionCapableOllamaModelWhenVisualAssetIsProvided() async throws {
        let visual = DocumentVisualAsset(
            id: UUID(),
            pageIndex: 8,
            kind: .pageSnapshot,
            imageData: Data([0xAA, 0xBB, 0xCC]),
            pixelWidth: 1200,
            pixelHeight: 900,
            suggestedFilename: "transformers-page-9-visual.png"
        )
        let ollamaGenerator = StubOllamaGenerator(result: "Visual answer")
        let assistant = DocumentAssistant(
            extractor: StubDocumentContextExtractor(
                result: DocumentContext(
                    title: "Transformers",
                    excerpt: "The current page describes an encoder-decoder workflow."
                )
            ),
            ollamaGenerator: ollamaGenerator,
            claudeGenerator: StubClaudeGenerator(result: "Claude answer")
        )

        let answer = try await assistant.answer(
            question: "Explain this diagram.",
            for: ReaderDocument(fileURL: URL(fileURLWithPath: "/tmp/Transformers.pdf")),
            providerStatuses: [
                AIProviderStatus(kind: .ollama, isAvailable: true, detail: "ready", models: ["llama3.2", "llava:latest"]),
                AIProviderStatus(kind: .claudeCLI, isAvailable: true, detail: "ready", models: [])
            ],
            scope: .focus,
            visualAsset: visual
        )

        #expect(answer == "Visual answer")
        #expect(await ollamaGenerator.lastModel == "llava:latest")
        #expect(await ollamaGenerator.lastImageData == visual.imageData)
        #expect(await ollamaGenerator.lastPrompt?.contains("Explain this diagram.") == true)
    }

    @Test
    func answerFailsClearlyWhenVisualAssetIsProvidedWithoutVisionModel() async throws {
        let visual = DocumentVisualAsset(
            id: UUID(),
            pageIndex: 3,
            kind: .embeddedImage,
            imageData: Data([0x10, 0x20, 0x30]),
            pixelWidth: 640,
            pixelHeight: 480,
            suggestedFilename: "agents-page-4-figure.png"
        )
        let assistant = DocumentAssistant(
            extractor: StubDocumentContextExtractor(
                result: DocumentContext(
                    title: "Agent Mesh",
                    excerpt: "The current section includes a multi-agent coordination diagram."
                )
            ),
            ollamaGenerator: StubOllamaGenerator(result: "unused"),
            claudeGenerator: StubClaudeGenerator(result: "unused")
        )

        await #expect(throws: DocumentAssistantError.noVisionCapableProvider) {
            try await assistant.answer(
                question: "Explain this diagram.",
                for: ReaderDocument(fileURL: URL(fileURLWithPath: "/tmp/Agent Mesh.pdf")),
                providerStatuses: [
                    AIProviderStatus(kind: .ollama, isAvailable: true, detail: "ready", models: ["llama3.2"]),
                    AIProviderStatus(kind: .claudeCLI, isAvailable: true, detail: "ready", models: [])
                ],
                scope: .focus,
                selection: nil,
                currentPageIndex: nil,
                visiblePageIndexes: [],
                visualAsset: visual
            )
        }
    }

    @Test
    func answerFailsWithVisionSpecificErrorWhenOnlyClaudeIsAvailable() async throws {
        let visual = DocumentVisualAsset(
            id: UUID(),
            pageIndex: 5,
            kind: .pageSnapshot,
            imageData: Data([0x01, 0x02, 0x03]),
            pixelWidth: 1024,
            pixelHeight: 768,
            suggestedFilename: "distributed-systems-page-6-diagram.png"
        )
        let assistant = DocumentAssistant(
            extractor: StubDocumentContextExtractor(
                result: DocumentContext(
                    title: "Distributed Systems",
                    excerpt: "This page includes a quorum write diagram."
                )
            ),
            ollamaGenerator: StubOllamaGenerator(result: "unused"),
            claudeGenerator: StubClaudeGenerator(result: "unused")
        )

        await #expect(throws: DocumentAssistantError.noVisionCapableProvider) {
            try await assistant.answer(
                question: "Explain this diagram.",
                for: ReaderDocument(fileURL: URL(fileURLWithPath: "/tmp/Distributed Systems.pdf")),
                providerStatuses: [
                    AIProviderStatus(kind: .claudeCLI, isAvailable: true, detail: "ready", models: [])
                ],
                scope: .focus,
                selection: nil,
                currentPageIndex: nil,
                visiblePageIndexes: [],
                visualAsset: visual
            )
        }
    }
}

private struct StubDocumentContextExtractor: DocumentContextExtracting {
    let result: DocumentContext

    func extractContext(
        for document: ReaderDocument,
        question: String,
        scope: DocumentQueryScope,
        selection: DocumentSelection?,
        currentPageIndex: Int?,
        visiblePageIndexes: [Int],
        isCancelled: @escaping @Sendable () -> Bool,
        onProgress: @escaping @Sendable (PageScanProgress) -> Void
    ) throws -> DocumentContext {
        result
    }
}

private final class RecordingDocumentContextExtractor: @unchecked Sendable, DocumentContextExtracting {
    struct Call: Equatable {
        let question: String
        let scope: DocumentQueryScope
        let selection: DocumentSelection?
        let currentPageIndex: Int?
        let visiblePageIndexes: [Int]
    }

    private(set) var lastCall: Call?
    let result: DocumentContext

    init(result: DocumentContext) {
        self.result = result
    }

    func extractContext(
        for document: ReaderDocument,
        question: String,
        scope: DocumentQueryScope,
        selection: DocumentSelection?,
        currentPageIndex: Int?,
        visiblePageIndexes: [Int],
        isCancelled: @escaping @Sendable () -> Bool,
        onProgress: @escaping @Sendable (PageScanProgress) -> Void
    ) throws -> DocumentContext {
        lastCall = Call(
            question: question,
            scope: scope,
            selection: selection,
            currentPageIndex: currentPageIndex,
            visiblePageIndexes: visiblePageIndexes
        )
        return result
    }
}

private actor StubOllamaGenerator: OllamaGenerating {
    private(set) var lastModel: String?
    private(set) var lastPrompt: String?
    private(set) var lastImageData: Data?
    private(set) var callCount = 0
    let result: String

    init(result: String) {
        self.result = result
    }

    func generate(model: String, prompt: String, imageData: Data?) async throws -> String {
        lastModel = model
        lastPrompt = prompt
        lastImageData = imageData
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
