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
        visualAsset: DocumentVisualAsset? = nil,
        onProgress: @escaping @Sendable (DocumentAssistantProgress) -> Void = { _ in }
    ) async throws -> String {
        let target = try executionTarget(from: providerStatuses, requiresVision: visualAsset != nil)

        // Text extraction walks every page synchronously; keep it off the calling
        // actor and let task cancellation stop it between pages.
        let extractor = extractor
        let context = try await BlockingWork.run { isCancelled in
            try extractor.extractContext(
                for: document,
                question: question,
                scope: scope,
                selection: selection,
                currentPageIndex: currentPageIndex,
                visiblePageIndexes: visiblePageIndexes,
                isCancelled: isCancelled,
                onProgress: { onProgress(.extractingContext($0)) }
            )
        }
        let prompt = buildPrompt(question: question, scope: scope, context: context, visualAsset: visualAsset)

        switch target {
        case let .ollama(model):
            onProgress(.generating(model: model))
            return try await ollamaGenerator.generate(model: model, prompt: prompt, imageData: visualAsset?.imageData)
        case .claude:
            onProgress(.generating(model: AIProviderKind.claudeCLI.displayName))
            return try await claudeGenerator.generate(prompt: prompt)
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

    /// Decided before any page text is read, so an unanswerable request fails
    /// without paying for the extraction.
    private func executionTarget(from providerStatuses: [AIProviderStatus], requiresVision: Bool) throws -> ExecutionTarget {
        if requiresVision {
            guard let model = providerStatuses.compactMap(\.preferredVisionModel).first else {
                throw DocumentAssistantError.noVisionCapableProvider
            }

            return .ollama(model: model)
        }

        if let blocker = providerStatuses.textAnswerBlocker {
            throw blocker
        }

        if let model = providerStatuses.compactMap(\.preferredChatModel).first {
            return .ollama(model: model)
        }

        return .claude
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
}
