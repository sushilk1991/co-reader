struct DocumentAssistant: DocumentAssisting {
    let extractor: DocumentContextExtracting
    let ollamaGenerator: OllamaGenerating
    let claudeGenerator: ClaudeGenerating

    init(
        extractor: DocumentContextExtracting = LiveDocumentContextExtractor(),
        ollamaGenerator: OllamaGenerating = OllamaGenerationClient(),
        claudeGenerator: ClaudeGenerating = ClaudeCodeClient()
    ) {
        self.extractor = extractor
        self.ollamaGenerator = ollamaGenerator
        self.claudeGenerator = claudeGenerator
    }

    func answer(
        question: String,
        for document: ReaderDocument,
        providerStatuses: [AIProviderStatus],
        selection: DocumentSelection? = nil,
        currentPageIndex: Int? = nil,
        visiblePageIndexes: [Int] = []
    ) async throws -> String {
        let context = try extractor.extractContext(
            for: document,
            question: question,
            selection: selection,
            currentPageIndex: currentPageIndex,
            visiblePageIndexes: visiblePageIndexes
        )
        let prompt = buildPrompt(question: question, context: context)

        switch preferredExecutionTarget(from: providerStatuses) {
        case let .ollama(model):
            return try await ollamaGenerator.generate(model: model, prompt: prompt)
        case .claude:
            return try await claudeGenerator.generate(prompt: prompt)
        case .unavailable:
            throw DocumentAssistantError.noAvailableProvider
        }
    }

    private func buildPrompt(question: String, context: DocumentContext) -> String {
        """
        You are Co-Reader, an AI study partner for dense technical documents.
        Answer using the provided document context first. If the excerpt is incomplete, say what is uncertain instead of inventing details.

        Document Title:
        \(context.title)

        Document Excerpt:
        \(context.excerpt)

        User Question:
        \(question)

        Response Style:
        - Start with a direct answer.
        - Use short bullet points when they improve clarity.
        - Mention uncertainty explicitly if the excerpt is incomplete.
        """
    }

    private func preferredExecutionTarget(from providerStatuses: [AIProviderStatus]) -> ExecutionTarget {
        if let ollama = providerStatuses.first(where: { $0.kind == .ollama && $0.isAvailable && !$0.models.isEmpty }) {
            return .ollama(model: ollama.models[0])
        }

        if providerStatuses.contains(where: { $0.kind == .claudeCLI && $0.isAvailable }) {
            return .claude
        }

        return .unavailable
    }
}

private enum ExecutionTarget {
    case ollama(model: String)
    case claude
    case unavailable
}
