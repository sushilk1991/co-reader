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
}

private struct StubDocumentAssistant: DocumentAssisting {
    let result: String

    func answer(
        question: String,
        for document: ReaderDocument,
        providerStatuses: [AIProviderStatus]
    ) async throws -> String {
        result
    }
}
