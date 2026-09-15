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

    @Test
    func summarizeQuickActionAdaptsToDocumentScope() async throws {
        let appModel = AppModel(documentAssistant: StubDocumentAssistant(result: "Summary created."))
        appModel.providerStatuses = [
            AIProviderStatus(kind: .ollama, isAvailable: true, detail: "ready", models: ["llama3.2"])
        ]
        appModel.importDocument(from: URL(fileURLWithPath: "/tmp/Distributed Systems.pdf"))
        appModel.queryScope = .document

        await appModel.runQuickAction(.summarize)

        #expect(appModel.chatTranscript.count == 2)
        #expect(appModel.chatTranscript[0].content.contains("whole document"))
        #expect(appModel.chatTranscript[1].content == "Summary created.")
    }

    /// Cancelling during Ollama generation surfaces as `URLError.cancelled`, not
    /// `CancellationError`; the transcript must still say it was cancelled, not errored.
    @Test
    func urlSessionCancellationIsLabelledAsCancelled() async throws {
        let appModel = AppModel(documentAssistant: ThrowingURLCancelledAssistant())
        appModel.providerStatuses = [
            AIProviderStatus(kind: .ollama, isAvailable: true, detail: "ready", models: ["llama3.2"])
        ]
        appModel.importDocument(from: URL(fileURLWithPath: "/tmp/Distributed Systems.pdf"))
        appModel.chatInput = "What is the core idea?"

        await appModel.askQuestion()

        #expect(appModel.chatError == nil)
        #expect(appModel.chatTranscript.map(\.content) == ["What is the core idea?", "Cancelled before an answer arrived."])
    }

    /// A second ask while the first is in flight supersedes it: the first must not
    /// clear the in-progress state or write a cancelled line under the second question.
    @Test
    func supersededAskLeavesTheNewAskInProgress() async throws {
        let assistant = GatedAssistant(result: "Second answer")
        let appModel = AppModel(documentAssistant: assistant)
        appModel.providerStatuses = [
            AIProviderStatus(kind: .ollama, isAvailable: true, detail: "ready", models: ["llama3.2"])
        ]
        appModel.importDocument(from: URL(fileURLWithPath: "/tmp/Distributed Systems.pdf"))

        appModel.chatInput = "First?"
        let first = Task { await appModel.askQuestion() }
        await waitUntil { assistant.callCount == 1 }

        appModel.chatInput = "Second?"
        let second = Task { await appModel.askQuestion() }
        await waitUntil { assistant.callCount == 2 }
        await first.value

        #expect(appModel.isAskingQuestion)

        assistant.release()
        await second.value

        #expect(appModel.isAskingQuestion == false)
        #expect(appModel.chatTranscript.map(\.content) == ["First?", "Second?", "Second answer"])
    }
}

private struct StubDocumentAssistant: DocumentAssisting {
    let result: String

    func answer(
        question: String,
        for document: ReaderDocument,
        providerStatuses: [AIProviderStatus],
        scope: DocumentQueryScope,
        selection: DocumentSelection?,
        currentPageIndex: Int?,
        visiblePageIndexes: [Int],
        visualAsset: DocumentVisualAsset?,
        onProgress: @escaping @Sendable (DocumentAssistantProgress) -> Void
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

private struct ThrowingURLCancelledAssistant: DocumentAssisting {
    func answer(
        question: String,
        for document: ReaderDocument,
        providerStatuses: [AIProviderStatus],
        scope: DocumentQueryScope,
        selection: DocumentSelection?,
        currentPageIndex: Int?,
        visiblePageIndexes: [Int],
        visualAsset: DocumentVisualAsset?,
        onProgress: @escaping @Sendable (DocumentAssistantProgress) -> Void
    ) async throws -> String {
        throw URLError(.cancelled)
    }
}

/// Holds every answer until `release()`; cancellation ends the wait early.
@MainActor
private final class GatedAssistant: DocumentAssisting {
    private(set) var callCount = 0
    private var isReleased = false
    private let result: String

    init(result: String) {
        self.result = result
    }

    func release() {
        isReleased = true
    }

    func answer(
        question: String,
        for document: ReaderDocument,
        providerStatuses: [AIProviderStatus],
        scope: DocumentQueryScope,
        selection: DocumentSelection?,
        currentPageIndex: Int?,
        visiblePageIndexes: [Int],
        visualAsset: DocumentVisualAsset?,
        onProgress: @escaping @Sendable (DocumentAssistantProgress) -> Void
    ) async throws -> String {
        callCount += 1
        while !isReleased {
            try await Task.sleep(for: .milliseconds(5))
        }

        return result
    }
}
