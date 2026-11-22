import Foundation

/// Shared patterns for the two identifiers papers carry.
public enum PaperIdentifier: Sendable, Equatable {
    /// Without the version suffix: "1706.03762" or "hep-th/9901001".
    case arxiv(String)
    /// Lowercased, without resolver prefix: "10.1038/nature14539".
    case doi(String)

    /// Reads what people paste: an arXiv abs/pdf link, "arXiv:1706.03762v5", a bare arXiv
    /// id, a doi.org link, "doi:10...." or a bare DOI. Nil when it is none of those.
    public static func parse(_ input: String) -> PaperIdentifier? {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        // "arxiv.org/abs/..." pasted without a scheme is still a link.
        if !text.contains("://"), text.range(of: #"^(www\.)?([a-z0-9]+\.)?(arxiv|doi)\.org/"#, options: [.regularExpression, .caseInsensitive]) != nil {
            text = "https://" + text
        }

        if let url = URL(string: text), let host = url.host?.lowercased() {
            let path = url.path.removingPercentEncoding ?? url.path
            if host.hasSuffix("arxiv.org") || host.hasSuffix("alphaxiv.org") || host.hasSuffix("ar5iv.org")
                || host.hasSuffix("ar5iv.labs.arxiv.org") {
                // /abs/<id>, /pdf/<id>(.pdf), /html/<id>
                let parts = path.split(separator: "/").map(String.init)
                if let marker = parts.firstIndex(where: { ["abs", "pdf", "html", "format"].contains($0) }),
                   marker + 1 < parts.count {
                    var candidate = parts[(marker + 1)...].joined(separator: "/")
                    if candidate.lowercased().hasSuffix(".pdf") { candidate.removeLast(4) }
                    if let id = arxivID(exactly: candidate) { return .arxiv(id) }
                }
                return nil
            }
            if host == "doi.org" || host == "dx.doi.org" || host.hasSuffix(".doi.org") {
                return doi(in: path).map(identifier(forDOI:))
            }
            // Publisher links often carry the DOI in the path.
            if let found = doi(in: path) { return identifier(forDOI: found) }
            return nil
        }

        let lower = text.lowercased()
        if lower.hasPrefix("arxiv:") {
            return arxivID(exactly: String(text.dropFirst(6)).trimmingCharacters(in: .whitespaces)).map(PaperIdentifier.arxiv)
        }
        if lower.hasPrefix("doi:") {
            return doi(in: String(text.dropFirst(4))).map(identifier(forDOI:))
        }
        if let id = arxivID(exactly: text) { return .arxiv(id) }
        if lower.hasPrefix("10."), let found = doi(in: text) { return identifier(forDOI: found) }
        return nil
    }

    /// arXiv's own DOIs (10.48550/arXiv.<id>) are registered with DataCite, not Crossref,
    /// so they have to be looked up as arXiv ids.
    static func identifier(forDOI doi: String) -> PaperIdentifier {
        let prefix = "10.48550/arxiv."
        if doi.hasPrefix(prefix), let id = arxivID(exactly: String(doi.dropFirst(prefix.count))) {
            return .arxiv(id)
        }
        return .doi(doi)
    }

    // MARK: Patterns

    /// New style 2301.01234 (optionally v2); old style hep-th/9901001 or math.AG/0601001.
    static let arxivCore = #"(?:\d{4}\.\d{4,5}|[a-z\-]+(?:\.[A-Za-z]{2})?/\d{7})"#

    /// The whole string is an arXiv id; returns it without the version.
    static func arxivID(exactly text: String) -> String? {
        let pattern = try! NSRegularExpression(pattern: "^(\(arxivCore))(?:v\\d+)?$", options: [.caseInsensitive])
        let range = NSRange(text.startIndex..., in: text)
        guard let match = pattern.firstMatch(in: text, range: range), let r = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return normalizedArxiv(String(text[r]))
    }

    /// First "arXiv:<id>" stamp or arxiv.org link in running text.
    static func arxivID(in text: String) -> String? {
        let pattern = try! NSRegularExpression(
            pattern: "(?:arxiv\\s*:\\s*|arxiv\\.org/(?:abs|pdf)/)(\(arxivCore))",
            options: [.caseInsensitive]
        )
        let range = NSRange(text.startIndex..., in: text)
        guard let match = pattern.firstMatch(in: text, range: range), let r = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return normalizedArxiv(String(text[r]))
    }

    private static func normalizedArxiv(_ id: String) -> String {
        // Old-style archive names are lower case; the subject class keeps its capitals.
        guard let slash = id.firstIndex(of: "/") else { return id }
        let archive = id[..<slash]
        if let dot = archive.firstIndex(of: ".") {
            return archive[..<dot].lowercased() + archive[dot...].uppercased() + id[slash...]
        }
        return archive.lowercased() + id[slash...]
    }

    /// First DOI in the text, lowercased, with trailing sentence punctuation removed.
    static func doi(in text: String) -> String? {
        let pattern = try! NSRegularExpression(pattern: #"10\.\d{4,9}/[^\s"<>]+"#)
        let range = NSRange(text.startIndex..., in: text)
        guard let match = pattern.firstMatch(in: text, range: range), let r = Range(match.range, in: text) else {
            return nil
        }
        var doi = String(text[r])
        while let last = doi.last, ".,;:)]}'".contains(last) {
            // A closing bracket belongs to the DOI when its opener is inside it.
            if last == ")", doi.filter({ $0 == "(" }).count >= doi.filter({ $0 == ")" }).count { break }
            doi.removeLast()
        }
        return doi.isEmpty ? nil : doi.lowercased()
    }
}
