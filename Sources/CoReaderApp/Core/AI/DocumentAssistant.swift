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
        scope: DocumentQueryScope,
        selection: DocumentSelection? = nil,
        currentPageIndex: Int? = nil,
        visiblePageIndexes: [Int] = [],
        visualAsset: DocumentVisualAsset? = nil
    ) async throws -> String {
        let context = try extractor.extractContext(
            for: document,
            question: question,
            scope: scope,
            selection: selection,
            currentPageIndex: currentPageIndex,
            visiblePageIndexes: visiblePageIndexes
        )
        let prompt = buildPrompt(question: question, scope: scope, context: context, visualAsset: visualAsset)

        switch preferredExecutionTarget(from: providerStatuses, requiresVision: visualAsset != nil) {
        case let .ollama(model):
            return try await ollamaGenerator.generate(model: model, prompt: prompt, imageData: visualAsset?.imageData)
        case .claude:
            return try await claudeGenerator.generate(prompt: prompt)
        case .unavailableVision:
            throw DocumentAssistantError.noVisionCapableProvider
        case .unavailable:
            throw DocumentAssistantError.noAvailableProvider
        }
    }

    private func buildPrompt(question: String, scope: DocumentQueryScope, context: DocumentContext, visualAsset: DocumentVisualAsset?) -> String {
        """
        You are Co-Reader, an AI study partner for dense technical documents.
        Answer using the provided document context first. If the excerpt is incomplete, say what is uncertain instead of inventing details.

        Document Title:
        \(context.title)

        Requested Scope:
        \(scope.contextHeading)

        Document Excerpt:
        \(context.excerpt)

        Visual Context:
        \(visualPromptContext(for: visualAsset))

        User Question:
        \(question)

        Response Style:
        - Start with a direct answer.
        - Use short bullet points when they improve clarity.
        - When multiple pages or chapters are included, synthesize only what the excerpts support.
        - Mention uncertainty explicitly if the excerpt is incomplete.
        """
    }

    private func preferredExecutionTarget(from providerStatuses: [AIProviderStatus], requiresVision: Bool) -> ExecutionTarget {
        if requiresVision {
            if let model = providerStatuses
                .compactMap(\.preferredVisionModel)
                .first {
                return .ollama(model: model)
            }

            return .unavailableVision
        }

        if let ollama = providerStatuses.first(where: { $0.kind == .ollama && $0.isAvailable && !$0.models.isEmpty }) {
            return .ollama(model: ollama.models[0])
        }

        if providerStatuses.contains(where: { $0.kind == .claudeCLI && $0.isAvailable }) {
            return .claude
        }

        return .unavailable
    }

    private func visualPromptContext(for visualAsset: DocumentVisualAsset?) -> String {
        guard let visualAsset else {
            return "No image attached."
        }

        return """
        An image is attached from page \(visualAsset.pageIndex + 1).
        Image type: \(visualAsset.kind.rawValue).
        Pixel size: \(visualAsset.pixelWidth)x\(visualAsset.pixelHeight).
        """
    }
}

private enum ExecutionTarget {
    case ollama(model: String)
    case claude
    case unavailableVision
    case unavailable
}
