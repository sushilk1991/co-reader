struct NoOpKnowledgeCapture: KnowledgeCapturing {
    func capture(question: String, answer: String, for document: ReaderDocument) throws {}
}
