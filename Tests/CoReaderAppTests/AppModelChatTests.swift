import Foundation
import Testing
@testable import CoReaderApp

@MainActor
struct AppModelChatTests {
    @Test
    func askQuestionAppendsUserAndAssistantTurns() async throws {
        let appModel = AppModel(documentAssistant: StubDocumentAssistant(result: "Distributed consensus keeps readers aligned."))
        appModel.providerStatuses = [
            AIProviderStatus(kind: .ollama, isAvailable: true, detail: "ready", models: ["llama3.2"])
        ]
        appModel.importDocument(from: URL(fileURLWithPath: "/tmp/Distributed Systems.pdf"))
        appModel.chatInput = "What is the core idea?"

        await appModel.askQuestion()

        #expect(appModel.chatInput.isEmpty)
        #expect(appModel.chatTranscript.count == 2)
        #expect(appModel.chatTranscript[0].role == .user)
        #expect(appModel.chatTranscript[1].role == .assistant)
        #expect(appModel.chatTranscript[1].content == "Distributed consensus keeps readers aligned.")
    }

    @Test
    func askQuestionCapturesKnowledgeAfterAnswering() async throws {
        let capture = StubKnowledgeCapture()
        let appModel = AppModel(
            documentAssistant: StubDocumentAssistant(result: "Notes should be captured."),
            knowledgeCapture: capture
        )
        appModel.providerStatuses = [
            AIProviderStatus(kind: .ollama, isAvailable: true, detail: "ready", models: ["llama3.2"])
        ]
        appModel.importDocument(from: URL(fileURLWithPath: "/tmp/Distributed Systems.pdf"))
        appModel.chatInput = "Summarize the tradeoffs."

        await appModel.askQuestion()

        #expect(capture.capturedQuestions == ["Summarize the tradeoffs."])
    }

    @Test
    func quickActionUsesPromptTemplateAndAsksQuestion() async throws {
        let appModel = AppModel(documentAssistant: StubDocumentAssistant(result: "Quiz created."))
        appModel.providerStatuses = [
            AIProviderStatus(kind: .ollama, isAvailable: true, detail: "ready", models: ["llama3.2"])
        ]
        appModel.importDocument(from: URL(fileURLWithPath: "/tmp/Advanced Algorithms.pdf"))

        await appModel.runQuickAction(.quizMe)

        #expect(appModel.chatTranscript.count == 2)
        #expect(appModel.chatTranscript[0].content.contains("short quiz"))
        #expect(appModel.chatTranscript[0].content.contains("Advanced Algorithms"))
        #expect(appModel.chatTranscript[1].content == "Quiz created.")
    }
}

private struct StubDocumentAssistant: DocumentAssisting {
    let result: String

    func answer(
        question: String,
        for document: ReaderDocument,
        providerStatuses: [AIProviderStatus],
        selection: DocumentSelection?,
        currentPageIndex: Int?,
        visiblePageIndexes: [Int]
    ) async throws -> String {
        result
    }
}

@MainActor
private final class StubKnowledgeCapture: KnowledgeCapturing {
    private(set) var capturedQuestions: [String] = []

    func capture(question: String, answer: String, for document: ReaderDocument) throws {
        capturedQuestions.append(question)
    }
}
