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

    func delete(noteID: UUID) throws {
        try FileManager.default.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
        let prefix = noteID.uuidString.lowercased()
        let candidateFiles = try FileManager.default.contentsOfDirectory(
            at: baseDirectory,
            includingPropertiesForKeys: nil
        )

        for fileURL in candidateFiles where fileURL.lastPathComponent.hasPrefix(prefix) {
            try FileManager.default.removeItem(at: fileURL)
        }
    }

    /// Reads every note file back. Files that do not carry the metadata block this
    /// store writes are skipped rather than guessed at.
    func loadNotes() throws -> [StoredKnowledgeNote] {
        guard FileManager.default.fileExists(atPath: baseDirectory.path) else {
            return []
        }

        let fileURLs = try FileManager.default.contentsOfDirectory(
            at: baseDirectory,
            includingPropertiesForKeys: nil
        )

        return fileURLs
            .filter { $0.pathExtension.lowercased() == "md" }
            .compactMap { fileURL in
                guard let markdown = try? String(contentsOf: fileURL, encoding: .utf8),
                      let note = MarkdownNoteParser.note(from: markdown) else {
                    return nil
                }

                return StoredKnowledgeNote(note: note, fileURL: fileURL)
            }
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
        lines.append("- Note Type: \(note.kind.rawValue)")
        lines.append("- Created At: \(ISO8601DateFormatter().string(from: note.createdAt))")

        if let pageIndex = note.pageIndex {
            lines.append("- Page: \(pageIndex + 1)")
        }

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

struct StoredKnowledgeNote: Equatable, Sendable {
    let note: KnowledgeNote
    let fileURL: URL
}

/// Inverse of `MarkdownKnowledgeStore.markdown(for:)`.
///
/// ```
///  # Title                      → title
///  ## Key Takeaways / - item    → bulletPoints
///  ## Source / <line>           → sourceIdentifier
///  ## Highlight / > quote       → highlightExcerpt
///  ## Metadata / - Key: Value   → id, kind, createdAt, pageIndex
/// ```
private enum MarkdownNoteParser {
    private static let takeawaysSection = "Key Takeaways"
    private static let sourceSection = "Source"
    private static let highlightSection = "Highlight"
    private static let metadataSection = "Metadata"
    private static let savedFromPrefix = "Saved from"

    static func note(from markdown: String) -> KnowledgeNote? {
        var title = ""
        var bulletPoints: [String] = []
        var sourceIdentifier = ""
        var highlightLines: [String] = []
        var metadata: [String: String] = [:]
        var section = ""

        for rawLine in markdown.components(separatedBy: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)

            if line.hasPrefix("# "), section.isEmpty, title.isEmpty {
                title = String(line.dropFirst(2))
                continue
            }

            if line.hasPrefix("## ") {
                section = String(line.dropFirst(3))
                continue
            }

            guard !line.isEmpty else {
                continue
            }

            switch section {
            case takeawaysSection where line.hasPrefix("- "):
                bulletPoints.append(String(line.dropFirst(2)))
            case sourceSection where sourceIdentifier.isEmpty:
                sourceIdentifier = line
            case highlightSection where line.hasPrefix("> "):
                highlightLines.append(String(line.dropFirst(2)))
            case metadataSection where line.hasPrefix("- "):
                let parts = line.dropFirst(2).split(separator: ":", maxSplits: 1)
                guard parts.count == 2 else { continue }
                metadata[parts[0].trimmingCharacters(in: .whitespaces)] = parts[1].trimmingCharacters(in: .whitespaces)
            default:
                continue
            }
        }

        guard !title.isEmpty,
              let id = metadata["Note ID"].flatMap(UUID.init(uuidString:)),
              let createdAt = metadata["Created At"].flatMap(ISO8601DateFormatter().date(from:)) else {
            return nil
        }

        let kind = metadata["Note Type"].flatMap(KnowledgeNoteKind.init(rawValue:)) ?? .note
        let pageIndex = metadata["Page"].flatMap(Int.init).map { $0 - 1 }

        return KnowledgeNote(
            id: id,
            kind: kind,
            title: title,
            sourceIdentifier: sourceIdentifier,
            createdAt: createdAt,
            bulletPoints: bulletPoints,
            highlightExcerpt: highlightLines.isEmpty ? nil : highlightLines.joined(separator: "\n"),
            pageIndex: pageIndex,
            notePreview: notePreview(kind: kind, bulletPoints: bulletPoints)
        )
    }

    /// The preview is not written to markdown; it is rebuilt the way each capture
    /// path derived it (note text = its lines, chat = first bullet, highlight = its note).
    private static func notePreview(kind: KnowledgeNoteKind, bulletPoints: [String]) -> String? {
        switch kind {
        case .note:
            return bulletPoints.isEmpty ? nil : bulletPoints.joined(separator: "\n")
        case .aiChat:
            return bulletPoints.first
        case .highlight:
            guard bulletPoints.count == 1, let only = bulletPoints.first, !only.hasPrefix(savedFromPrefix) else {
                return nil
            }
            return only
        }
    }
}
