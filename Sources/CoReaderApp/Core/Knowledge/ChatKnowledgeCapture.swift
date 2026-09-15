import Foundation

struct ChatKnowledgeCapture: KnowledgeCapturing {
    let repository: KnowledgeRepository

    init(repository: KnowledgeRepository) {
        self.repository = repository
    }

    func capture(question: String, answer: String, for document: ReaderDocument) throws {
        let bullets = summarize(answer: answer)
        let note = KnowledgeNote(
            id: UUID(),
            kind: .aiChat,
            title: "\(document.title) AI Chat",
            sourceIdentifier: document.noteSourceIdentifier,
            createdAt: Date(),
            bulletPoints: bullets,
            highlightExcerpt: question,
            pageIndex: nil,
            notePreview: bullets.first
        )

        try repository.save(note: note)
    }

    private func summarize(answer: String) -> [String] {
        let normalizedLines = answer
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .map(stripBulletPrefix)
            .filter { !$0.isEmpty }

        if normalizedLines.count > 1 {
            return Array(normalizedLines.prefix(5))
        }

        let sentences = answer
            .split(separator: ".")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { "\($0)." }

        if !sentences.isEmpty {
            return Array(sentences.prefix(5))
        }

        return [answer.trimmingCharacters(in: .whitespacesAndNewlines)]
    }

    private func stripBulletPrefix(from line: String) -> String {
        if line.hasPrefix("- ") || line.hasPrefix("* ") {
            return String(line.dropFirst(2))
        }

        return line.replacingOccurrences(
            of: #"^\d+\.\s+"#,
            with: "",
            options: .regularExpression
        )
    }
}
