import Foundation
import Observation

@MainActor
@Observable
final class AppModel {
    let appTitle = "Co-Reader"
    private let providerDiscovery: AIProviderDiscovery
    private let documentAssistant: DocumentAssisting
    private let knowledgeCapture: KnowledgeCapturing
    private var documentLibrary = DocumentLibrary()
    private(set) var hasLoadedProviders = false
    var isDiscoveringProviders = false
    var isImportingDocument = false
    var isAskingQuestion = false
    var capturedNoteCount = 0
    var providerStatuses: [AIProviderStatus] = []
    var selectedDocument: ReaderDocument?
    var chatInput = ""
    var chatError: String?
    var chatTranscript: [ChatMessage] = []

    init(
        providerDiscovery: AIProviderDiscovery = .live(),
        documentAssistant: DocumentAssisting = DocumentAssistant(),
        knowledgeCapture: KnowledgeCapturing = AppModel.defaultKnowledgeCapture()
    ) {
        self.providerDiscovery = providerDiscovery
        self.documentAssistant = documentAssistant
        self.knowledgeCapture = knowledgeCapture
    }

    var importedDocuments: [ReaderDocument] {
        documentLibrary.documents
    }

    var canSubmitQuestion: Bool {
        !chatInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            selectedDocument != nil &&
            !isAskingQuestion
    }

    var statusHeadline: String {
        if isDiscoveringProviders {
            return "Scanning local AI providers."
        }

        if providerStatuses.contains(where: \.isAvailable) {
            return "Local AI integrations are ready."
        }

        if hasLoadedProviders {
            return "No local AI providers were detected."
        }

        return "Local AI integrations are initializing."
    }

    var statusDetail: String {
        if isDiscoveringProviders {
            return "Checking Ollama on localhost:11434 and looking for the claude CLI."
        }

        if hasLoadedProviders {
            return "Use Ollama or Claude locally to ask document questions, explain figures, and generate code snippets."
        }

        return "The first provider scan starts automatically when the window opens."
    }

    func refreshProvidersIfNeeded() async {
        guard !hasLoadedProviders, !isDiscoveringProviders else {
            return
        }

        await refreshProviders()
    }

    func beginDocumentImport() {
        isImportingDocument = true
    }

    func importDocument(from url: URL) {
        let document = documentLibrary.importDocument(at: url)
        selectedDocument = document
    }

    func selectDocument(_ document: ReaderDocument) {
        selectedDocument = document
    }

    func askQuestion() async {
        let question = chatInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty else {
            return
        }

        guard let document = selectedDocument else {
            chatError = DocumentAssistantError.noSelectedDocument.localizedDescription
            return
        }

        chatError = nil
        chatInput = ""
        isAskingQuestion = true
        chatTranscript.append(ChatMessage(role: .user, content: question))
        defer { isAskingQuestion = false }

        do {
            let answer = try await documentAssistant.answer(
                question: question,
                for: document,
                providerStatuses: providerStatuses
            )
            chatTranscript.append(ChatMessage(role: .assistant, content: answer))

            do {
                try knowledgeCapture.capture(question: question, answer: answer, for: document)
                capturedNoteCount += 1
            } catch {
                chatError = "Answer generated, but note capture failed: \(error.localizedDescription)"
            }
        } catch {
            chatError = error.localizedDescription
            chatTranscript.append(ChatMessage(role: .assistant, content: error.localizedDescription))
        }
    }

    func refreshProviders() async {
        isDiscoveringProviders = true
        defer { isDiscoveringProviders = false }

        do {
            providerStatuses = try await providerDiscovery.discoverProviders()
        } catch {
            providerStatuses = AIProviderKind.allCases.map {
                AIProviderStatus(
                    kind: $0,
                    isAvailable: false,
                    detail: error.localizedDescription,
                    models: []
                )
            }
        }

        hasLoadedProviders = true
    }

    private static func defaultKnowledgeCapture() -> KnowledgeCapturing {
        guard let repository = try? KnowledgeRepository.liveDefault() else {
            return NoOpKnowledgeCapture()
        }

        return ChatKnowledgeCapture(repository: repository)
    }
}
