import Foundation
import Observation

@MainActor
@Observable
final class AppModel {
    let appTitle = "Co-Reader"
    private let providerDiscovery: AIProviderDiscovery
    private var documentLibrary = DocumentLibrary()
    private(set) var hasLoadedProviders = false
    var isDiscoveringProviders = false
    var isImportingDocument = false
    var providerStatuses: [AIProviderStatus] = []
    var selectedDocument: ReaderDocument?

    init(providerDiscovery: AIProviderDiscovery = .live()) {
        self.providerDiscovery = providerDiscovery
    }

    var importedDocuments: [ReaderDocument] {
        documentLibrary.documents
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
}
