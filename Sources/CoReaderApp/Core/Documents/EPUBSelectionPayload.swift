import Foundation

struct EPUBSelectionPayload: Codable, Equatable, Sendable {
    let text: String
    let surroundingText: String

    static func selection(fromMessageBody body: Any, chapterIndex: Int) -> DocumentSelection? {
        guard JSONSerialization.isValidJSONObject(body),
              let data = try? JSONSerialization.data(withJSONObject: body),
              let payload = try? JSONDecoder().decode(Self.self, from: data) else {
            return nil
        }

        return payload.documentSelection(chapterIndex: chapterIndex)
    }

    func documentSelection(chapterIndex: Int) -> DocumentSelection? {
        let normalizedText = normalized(text)
        guard let normalizedText, !normalizedText.isEmpty else {
            return nil
        }

        let normalizedContext = normalized(surroundingText) ?? normalizedText
        return DocumentSelection(
            text: normalizedText,
            pageIndex: chapterIndex,
            surroundingText: String(normalizedContext.prefix(2_000))
        )
    }

    private func normalized(_ value: String) -> String? {
        let trimmed = value
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return trimmed.isEmpty ? nil : trimmed
    }
}
