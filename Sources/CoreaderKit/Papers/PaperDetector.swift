import Foundation

public struct PaperHints: Sendable, Equatable {
    public var isLikelyPaper: Bool
    /// Without the version suffix, e.g. "2301.01234".
    public var arxivID: String?
    public var doi: String?
    public var guessedTitle: String?

    public init(isLikelyPaper: Bool, arxivID: String? = nil, doi: String? = nil, guessedTitle: String? = nil) {
        self.isLikelyPaper = isLikelyPaper
        self.arxivID = arxivID
        self.doi = doi
        self.guessedTitle = guessedTitle
    }
}

/// Decides whether an imported PDF is a research paper, from evidence that needs no
/// network: identifiers stamped on the first page, the usual section headings, the look
/// of two-column text, the page count and the file name.
public enum PaperDetector {
    public static func detect(firstPagesText: String, fileName: String, pdfTitle: String?, pageCount: Int) -> PaperHints {
        let text = firstPagesText
        let lines = text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }

        let fileStem = (fileName as NSString).deletingPathExtension
        let arxivFromName = PaperIdentifier.arxivID(exactly: fileStem)
        var arxiv = PaperIdentifier.arxivID(in: text) ?? arxivFromName
        var doi = PaperIdentifier.doi(in: text)
        if let found = doi, case .arxiv(let id) = PaperIdentifier.identifier(forDOI: found) {
            arxiv = arxiv ?? id
            doi = nil
        }

        var score = 0
        if arxiv != nil { score += 4 }
        if doi != nil { score += 2 }
        if hasHeading(lines, #"abstract"#) || text.range(of: #"\bAbstract\s*[—:.\-]"#, options: .regularExpression) != nil {
            score += 2
        }
        if hasHeading(lines, #"(?:(?:1|i)\.?\s+)?introduction"#) { score += 1 }
        if hasHeading(lines, #"(?:\d+\.?\s+)?(?:references|bibliography)"#) { score += 1 }
        if text.range(of: #"(?im)^\s*(keywords|index terms|key words)\b"#, options: .regularExpression) != nil { score += 1 }
        if text.range(of: #"(?i)\b(proceedings of|conference on|journal of|transactions on|preprint|under review|workshop on)\b"#,
                      options: .regularExpression) != nil { score += 1 }
        if text.range(of: #"(?i)\b(university|institute|laboratory|department of)\b"#, options: .regularExpression) != nil,
           text.contains("@") { score += 1 }
        if looksTwoColumn(lines) { score += 1 }

        // Books give themselves away too.
        if text.range(of: #"(?i)\b(isbn|table of contents|all rights reserved\. no part of this (book|publication))\b"#,
                      options: .regularExpression) != nil { score -= 2 }
        if text.range(of: #"(?im)^\s*chapter\s+(1|one|i)\b"#, options: .regularExpression) != nil { score -= 2 }
        if pageCount > 150 { score -= 3 } else if pageCount > 80 { score -= 1 } else if pageCount > 0, pageCount <= 40 { score += 1 }

        return PaperHints(
            isLikelyPaper: score >= 4,
            arxivID: arxiv,
            doi: doi,
            guessedTitle: guessTitle(pdfTitle: pdfTitle, lines: lines)
        )
    }

    // MARK: Structure cues

    /// A line that is nothing but the heading, in any case, optionally numbered.
    private static func hasHeading(_ lines: [String], _ pattern: String) -> Bool {
        lines.contains { $0.range(of: "^(?:\(pattern))\\s*$", options: [.regularExpression, .caseInsensitive]) != nil }
    }

    /// Two-column text extracts as many short lines, a good share of them broken with a
    /// hyphen in mid-word. Single-column books have longer lines and far fewer breaks.
    private static func looksTwoColumn(_ lines: [String]) -> Bool {
        let body = lines.filter { $0.count >= 25 }
        guard body.count >= 30 else { return false }
        let average = Double(body.reduce(0) { $0 + $1.count }) / Double(body.count)
        let hyphenated = body.filter { $0.range(of: #"[a-z]-$"#, options: .regularExpression) != nil }.count
        return average < 62 && Double(hyphenated) / Double(body.count) > 0.04
    }

    // MARK: Title

    static func guessTitle(pdfTitle: String?, lines: [String]) -> String? {
        if let title = pdfTitle?.split(whereSeparator: \.isWhitespace).joined(separator: " "), isUsableInfoTitle(title) {
            return title
        }
        // The title is the first real line of page one, before the abstract.
        let stop = lines.firstIndex { $0.range(of: #"^abstract\b"#, options: [.regularExpression, .caseInsensitive]) != nil }
        let head = Array(lines[..<(stop ?? min(lines.count, 25))].prefix(25))
        guard let first = head.firstIndex(where: isTitleLine) else { return nil }
        var title = head[first]
        // Long titles wrap; take the next line too when it reads as a continuation.
        if first + 1 < head.count {
            let next = head[first + 1]
            let endsOpen = title.range(of: #"(?i)(:|-|\b(of|for|and|with|in|on|to|the|a|an|via|from|by|using))$"#,
                                       options: .regularExpression) != nil
            let continues = next.first?.isLowercase == true
            if endsOpen || continues, !next.isEmpty, !next.contains("@"), !looksLikeAuthors(next) {
                title += " " + next
            }
        }
        return title
    }

    /// PDF info titles are often the name of the source file or of the typesetting tool.
    private static func isUsableInfoTitle(_ title: String) -> Bool {
        guard title.count >= 8, title.contains(" ") else { return false }
        let lower = title.lowercased()
        if lower.hasPrefix("microsoft word") || lower.hasPrefix("untitled") || lower.contains("latex") { return false }
        if lower.range(of: #"\.(pdf|docx?|tex|dvi|ps|indd|qxd)$"#, options: .regularExpression) != nil { return false }
        if PaperIdentifier.arxivID(in: title) != nil { return false }
        return true
    }

    private static func isTitleLine(_ line: String) -> Bool {
        guard line.count >= 12, line.count <= 200 else { return false }
        guard line.split(separator: " ").count >= 3 else { return false }
        let lower = line.lowercased()
        if lower.hasPrefix("arxiv:") || lower.contains("@") || lower.contains("http") || lower.contains("doi") { return false }
        if lower.range(of: #"(published|accepted|presented|appear|proceedings|conference|journal|preprint|copyright|©|vol\.|volume|permission|license|under review|submitted)"#,
                       options: .regularExpression) != nil { return false }
        let letters = line.filter(\.isLetter).count
        return Double(letters) / Double(line.count) > 0.7
    }

    /// "Ada Lovelace, Charles Babbage" or names with affiliation marks.
    private static func looksLikeAuthors(_ line: String) -> Bool {
        if line.range(of: #"[∗*†‡§\d]"#, options: .regularExpression) != nil { return true }
        let words = line.split(separator: " ")
        let capitalised = words.filter { $0.first?.isUppercase == true }.count
        return line.contains(",") && capitalised == words.count
    }
}
