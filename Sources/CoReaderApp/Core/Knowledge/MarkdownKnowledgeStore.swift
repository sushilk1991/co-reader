import Foundation

struct MarkdownKnowledgeStore {
    let baseDirectory: URL

    func save(note: KnowledgeNote) throws -> URL {
        try FileManager.default.createDirectory(at: baseDirectory, withIntermediateDirectories: true)

        let fileURL = noteFileURL(for: note)
        try markdown(for: note).write(to: fileURL, atomically: true, encoding: .utf8)
        return fileURL
    }

    func noteFileURL(for note: KnowledgeNote) -> URL {
        baseDirectory.appending(path: "\(note.id.uuidString.lowercased())-\(slug(from: note.title)).md")
    }

    private func markdown(for note: KnowledgeNote) -> String {
        var lines = [
            "# \(note.title)",
            "",
            "## Key Takeaways",
            ""
        ]

        lines.append(contentsOf: note.bulletPoints.map { "- \($0)" })
        lines.append("")
        lines.append("## Source")
        lines.append("")
        lines.append(note.sourceIdentifier)
        lines.append("")

        if let highlightExcerpt = note.highlightExcerpt, !highlightExcerpt.isEmpty {
            lines.append("## Highlight")
            lines.append("")
            lines.append("> \(highlightExcerpt)")
            lines.append("")
        }

        lines.append("## Metadata")
        lines.append("")
        lines.append("- Note ID: \(note.id.uuidString.lowercased())")
        lines.append("- Created At: \(ISO8601DateFormatter().string(from: note.createdAt))")

        return lines.joined(separator: "\n")
    }

    private func slug(from title: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-"))
        let slug = title
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .unicodeScalars
            .map { allowed.contains($0) ? Character($0) : "-" }
        let collapsed = String(slug).replacingOccurrences(of: "--+", with: "-", options: .regularExpression)
        return collapsed.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }
}
