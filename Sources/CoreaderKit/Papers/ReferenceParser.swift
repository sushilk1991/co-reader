import Foundation

/// One entry of a paper's bibliography.
public struct Reference: Sendable, Equatable, Codable, Identifiable {
    /// The label citations use: "12" for numbered styles, "Vaswani2017" for author-year.
    public var id: String
    /// The entry as printed, on one line, without its label.
    public var raw: String
    public var title: String?
    public var authors: [String]
    public var year: Int?
    public var doi: String?
    public var arxivID: String?

    public init(id: String, raw: String, title: String? = nil, authors: [String] = [], year: Int? = nil,
                doi: String? = nil, arxivID: String? = nil) {
        self.id = id
        self.raw = raw
        self.title = title
        self.authors = authors
        self.year = year
        self.doi = doi
        self.arxivID = arxivID
    }
}

/// Best-effort reading of bibliographies as they come out of PDF text extraction.
/// Citation styles are endless; this covers the common numbered and author-year shapes
/// and always keeps `raw`, so a miss on title or authors still shows the entry.
public enum ReferenceParser {
    // MARK: Finding the section

    public static func referencesSection(in fullText: String) -> String? {
        let lines = fullText.components(separatedBy: .newlines)
        let heading = regex(#"^\s*(?:\d+\.?\s+|[IVXL]+\.\s+)?(?:references(?: and notes)?|bibliography|literature cited|works cited|reference list)\s*:?\s*$"#,
                            [.caseInsensitive])
        // The last such heading: a table of contents may name the section earlier.
        guard let start = lines.lastIndex(where: { matches(heading, $0) }) else { return nil }
        let ending = regex(#"^\s*(?:[A-Z]\.?\s+)?(?:appendix|appendices|supplementary materials?|supplemental materials?|supporting information)\b"#,
                           [.caseInsensitive])
        var body: [String] = []
        for line in lines[(start + 1)...] {
            if matches(ending, line) { break }
            body.append(line)
        }
        let text = body.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    // MARK: Splitting into entries

    public static func parse(referencesText: String) -> [Reference] {
        let lines = referencesText.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            // Page numbers that the extraction left between entries.
            .filter { !matches(pageNumberLine, $0) }

        if let entries = labelled(lines, by: bracketLabel, sequential: false), entries.count >= 2 {
            return entries.map { makeReference(label: $0.label, raw: $0.text) }
        }
        if let entries = labelled(lines, by: numberLabel, sequential: true), entries.count >= 2 {
            return entries.map { makeReference(label: $0.label, raw: $0.text) }
        }

        var used: [String: Int] = [:]
        return unlabelled(lines).enumerated().map { index, text in
            var reference = makeReference(label: "", raw: text)
            reference.id = authorYearLabel(for: reference, index: index, used: &used)
            return reference
        }
    }

    private static let pageNumberLine = regex(#"^\d{1,4}$"#)
    private static let bracketLabel = regex(#"^\[([^\]\s]{1,24})\]\s*"#)
    private static let numberLabel = regex(#"^(\d{1,3})\.\s+(?=\S)"#)

    /// Entries that each start with a label. For bare "12." labels the numbers must count
    /// up one by one, or a line that happens to start with "2017. " would split an entry.
    private static func labelled(_ lines: [String], by pattern: NSRegularExpression, sequential: Bool) -> [(label: String, text: String)]? {
        var entries: [(label: String, lines: [String])] = []
        var expected: Int?
        for line in lines {
            if let match = pattern.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
               let labelRange = Range(match.range(at: 1), in: line), let whole = Range(match.range, in: line) {
                let label = String(line[labelRange])
                var accept = true
                if sequential {
                    let number = Int(label) ?? -1
                    accept = expected == nil ? number == 1 : number == expected
                    if accept { expected = number + 1 }
                }
                if accept {
                    entries.append((label, [String(line[whole.upperBound...])]))
                    continue
                }
            }
            if !entries.isEmpty, !line.isEmpty { entries[entries.count - 1].lines.append(line) }
        }
        guard !entries.isEmpty else { return nil }
        return entries.map { ($0.label, joinLines($0.lines)) }.filter { !$0.1.isEmpty }
    }

    /// Author-year lists have no labels. Blank lines separate entries when the extraction
    /// kept them; otherwise an entry ends where the next line starts like an author list.
    private static func unlabelled(_ lines: [String]) -> [String] {
        let paragraphs = lines.split(separator: "", omittingEmptySubsequences: true).map(Array.init)
        let withYear = paragraphs.filter { matches(anyYear, $0.joined(separator: " ")) }.count
        // Blank lines that fall between pages, not entries, leave long paragraphs behind.
        let lineCount = paragraphs.reduce(0) { $0 + $1.count }
        if paragraphs.count >= 2, withYear * 2 >= paragraphs.count, lineCount <= paragraphs.count * 5 {
            return paragraphs.map(joinLines)
        }
        var entries: [[String]] = []
        for line in lines where !line.isEmpty {
            if let last = entries.last {
                let soFar = last.joined(separator: " ")
                let complete = soFar.count >= 40 && matches(anyYear, soFar) && matches(entryEnd, last[last.count - 1])
                if complete, matches(authorStart, line) {
                    entries.append([line])
                } else {
                    entries[entries.count - 1].append(line)
                }
            } else {
                entries.append([line])
            }
        }
        return entries.map(joinLines)
    }

    private static let yearCore = #"(?:18|19|20)\d{2}"#
    private static let anyYear = regex(#"(?<!\d)(?:18|19|20)\d{2}[a-z]?(?!\d)"#)
    private static let entryEnd = regex(#"(?:[.\d)]|\.pdf|/)$"#)
    private static let nameWord = #"\p{Lu}[\p{L}'’\-]+"#
    /// "Vaswani, A.", "Ashish Vaswani,", "A. Vaswani" or "A. N. Gomez" at the start of a line.
    private static let authorStart = regex(
        "^(?:(?:(?:van|von|de|del|der|den|di|la|le)\\s+)*\(nameWord)(?:\\s\(nameWord)){0,3},"
            + "|(?:\\p{Lu}\\.[\\s\\-]?){1,3}\\s?\(nameWord)"
            + "|\(nameWord)(?:\\s(?:(?:van|von|de|del|der|den|di|la|le)\\s)*\(nameWord)){1,3}"
            + "(?:\\s+(?:and|&)\\s|\\.\\s+(?:18|19|20)\\d{2}))"
    )

    /// One line per entry, undoing the line breaks of the page: a word hyphenated at a line
    /// end is put back together.
    private static func joinLines(_ lines: [String]) -> String {
        var text = ""
        for line in lines where !line.isEmpty {
            if text.isEmpty {
                text = line
            } else if text.hasSuffix("-"), let before = text.dropLast().last, before.isLetter,
                      let first = line.first, first.isLowercase {
                text.removeLast()
                text += line
            } else {
                text += " " + line
            }
        }
        return text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    // MARK: Reading one entry

    static func makeReference(label: String, raw: String) -> Reference {
        var doi = PaperIdentifier.doi(in: raw)
        var arxiv = firstGroup(arxivInReference, raw)
        if let found = doi, case .arxiv(let id) = PaperIdentifier.identifier(forDOI: found) {
            arxiv = arxiv ?? id
            doi = nil
        }
        // Identifiers and links are full of digits that are not years, and of full stops
        // that are not sentence ends.
        var prose = raw
        for pattern in [urlPattern, doiPattern, arxivInReference] {
            prose = pattern.stringByReplacingMatches(in: prose, range: NSRange(prose.startIndex..., in: prose), withTemplate: " ")
        }
        prose = prose.split(whereSeparator: \.isWhitespace).joined(separator: " ")

        let (authors, title) = authorsAndTitle(prose)
        return Reference(id: label, raw: raw, title: title, authors: authors, year: year(in: prose), doi: doi, arxivID: arxiv)
    }

    private static let urlPattern = regex(#"https?://\S+"#)
    private static let doiPattern = regex(#"(?:doi\s*:?\s*)?10\.\d{4,9}/\S+"#, [.caseInsensitive])
    private static let arxivInReference = regex(
        "(?:arxiv\\s*:?\\s*|abs/)(\(PaperIdentifier.arxivCore))(?:v\\d+)?",
        [.caseInsensitive]
    )

    /// A year in brackets wins ("(2017)"); otherwise the last free-standing one, since
    /// most styles end with it. Page ranges like 1929–1958 are not years.
    private static func year(in text: String) -> Int? {
        let limit = Calendar(identifier: .gregorian).component(.year, from: Date()) + 1
        let bracketed = regex(#"\(((?:18|19|20)\d{2})[a-z]?[,)]"#)
        let free = regex(#"(?<![\d\-–—/:.])((?:18|19|20)\d{2})[a-z]?(?![\d\-–—/]|\.\d)"#)
        let candidates = allGroups(bracketed, text).first.map { [$0] } ?? Array(allGroups(free, text).reversed())
        return candidates.compactMap(Int.init).first { $0 <= limit }
    }

    private static func authorsAndTitle(_ text: String) -> (authors: [String], title: String?) {
        // IEEE and friends put the title in quotation marks.
        if let match = regex(#"[“"]([^”"]{8,})[”"]"#).firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
           let titleRange = Range(match.range(at: 1), in: text), let whole = Range(match.range, in: text) {
            return (splitAuthors(String(text[..<whole.lowerBound])), cleanTitle(String(text[titleRange])))
        }
        // APA: "Authors (2017). Title. Venue."
        if let match = regex(#"^(.{3,}?)\s*\((?:18|19|20)\d{2}[a-z]?(?:,[^)]*)?\)[.,:]?\s+(.+)$"#)
            .firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
           let authorRange = Range(match.range(at: 1), in: text), let restRange = Range(match.range(at: 2), in: text) {
            return (splitAuthors(String(text[authorRange])), cleanTitle(sentences(String(text[restRange])).first))
        }
        // "Kingma, D. P. and Ba, J. Adam: A method..." The list ends with an initial, so
        // sentence splitting cannot find its end; consume author by author instead.
        var rest = Substring(text)
        var inverted: [String] = []
        while let match = invertedAuthor.firstMatch(in: String(rest), range: NSRange(rest.startIndex..., in: rest)),
              let whole = Range(match.range, in: rest),
              let family = Range(match.range(at: 1), in: rest), let given = Range(match.range(at: 2), in: rest) {
            inverted.append(rest[given].trimmingCharacters(in: .whitespaces) + " " + rest[family])
            rest = rest[whole.upperBound...]
        }
        if !inverted.isEmpty {
            var remainder = String(rest)
            remainder = remainder.replacingOccurrences(of: #"^(?:et al\.?,?\s*)?(?:\(?(?:18|19|20)\d{2}[a-z]?\)?[.,:]?\s+)?"#,
                                                       with: "", options: .regularExpression)
            return (inverted, cleanTitle(sentences(remainder).first))
        }
        // "A. Vaswani, N. Shazeer, and I. Polosukhin. Attention is all you need. In ..."
        // or ACL's "Ashish Vaswani and Noam Shazeer. 2017. Attention is all you need."
        var parts = sentences(text)
        guard parts.count >= 2 else { return ([], nil) }
        let authors = splitAuthors(parts.removeFirst())
        while let next = parts.first, matches(regex(#"^\(?(?:18|19|20)\d{2}[a-z]?\)?$"#), next) { parts.removeFirst() }
        return (authors, cleanTitle(parts.first))
    }

    /// "Family, G. I.," with what joins it to the next author.
    private static let invertedAuthor = regex(
        "^(?:(?:and|&)\\s+)?((?:(?:van|von|de|del|der|den|di|la|le)\\s+)*\(nameWord)(?:\\s\(nameWord))?),\\s*"
            + "((?:\\p{Lu}\\.[\\s\\-]?)+)(?:[,;]\\s*|\\s+)?(?:(?:and|&)\\s+(?=\\p{Lu}))?"
    )

    private static func splitAuthors(_ text: String) -> [String] {
        // The final full stop may belong to an initial ("Polosukhin, I."), so it stays for now.
        var list = text.trimmingCharacters(in: CharacterSet(charactersIn: " ,;:"))
        list = list.replacingOccurrences(of: #",?\s*\bet al\b\.?"#, with: "", options: .regularExpression)
        // "Family, G." lists use commas inside each name, so they need the name pattern.
        if list.range(of: #"\p{Lu}[\p{L}'’\-]+,\s*\p{Lu}\."#, options: .regularExpression) != nil {
            var names: [String] = []
            var rest = Substring(list + ",")
            while let match = invertedAuthor.firstMatch(in: String(rest), range: NSRange(rest.startIndex..., in: rest)),
                  let whole = Range(match.range, in: rest),
                  let family = Range(match.range(at: 1), in: rest), let given = Range(match.range(at: 2), in: rest) {
                names.append(rest[given].trimmingCharacters(in: .whitespaces) + " " + rest[family])
                rest = rest[whole.upperBound...]
            }
            if !names.isEmpty { return names }
        }
        return list
            .replacingOccurrences(of: #"\s*(?:,\s*(?:and|&)\s+|\s+(?:and|&)\s+|;)\s*"#, with: ",", options: .regularExpression)
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: " .")) }
            .filter { name in
                // A real name: a few words, no digits. Anything else is a venue or a stray fragment.
                !name.isEmpty && name.split(separator: " ").count <= 5
                    && name.rangeOfCharacter(from: .decimalDigits) == nil && name.first?.isLetter == true
            }
    }

    private static func cleanTitle(_ text: String?) -> String? {
        guard var title = text?.trimmingCharacters(in: CharacterSet(charactersIn: " .,;:")) else { return nil }
        if title.hasPrefix("In ") && title.contains("Proceedings") { return nil }
        title = title.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return title.count >= 6 ? title : nil
    }

    /// Splits at full stops that end a sentence: not after an initial ("A. Vaswani"), not
    /// after a common abbreviation, and only before something that can start a sentence.
    static func sentences(_ text: String) -> [String] {
        let abbreviations: Set<String> = ["eds", "ed", "vol", "no", "pp", "proc", "conf", "int", "trans", "dept", "univ",
                                          "jr", "st", "vs", "fig", "inc", "corr", "eg", "ie", "cf"]
        var result: [String] = []
        var current = ""
        let characters = Array(text)
        var index = 0
        while index < characters.count {
            let character = characters[index]
            current.append(character)
            if character == "." || character == "?" || character == "!" {
                let next = index + 1 < characters.count ? characters[index + 1] : nil
                let afterSpace = index + 2 < characters.count ? characters[index + 2] : nil
                let atEnd = next == nil
                // Venues sometimes follow in lower case: "Title. arXiv preprint", "Title. in Proc.".
                let ahead = String(characters[min(index + 2, characters.count)...].prefix(5))
                let lowerStart = ahead.hasPrefix("arXiv") || ahead.hasPrefix("in ") || ahead.hasPrefix("http")
                let boundaryAhead = next == " "
                    && (lowerStart || (afterSpace.map { $0.isUppercase || $0.isNumber || "“\"(".contains($0) } ?? true))
                let word = current.dropLast().split(whereSeparator: { !$0.isLetter }).last.map(String.init) ?? ""
                let precededByLetter = current.dropLast().last?.isLetter ?? false
                let isInitial = character == "." && precededByLetter && word.count == 1 && word.first?.isUppercase == true
                let isAbbreviation = character == "." && precededByLetter && abbreviations.contains(word.lowercased())
                if atEnd || (boundaryAhead && !isInitial && !isAbbreviation) {
                    let sentence = current.trimmingCharacters(in: .whitespaces)
                    if !sentence.isEmpty { result.append(String(sentence.dropLast()).trimmingCharacters(in: .whitespaces)) }
                    current = ""
                }
            }
            index += 1
        }
        let tail = current.trimmingCharacters(in: .whitespaces)
        if !tail.isEmpty { result.append(tail) }
        return result.filter { !$0.isEmpty }
    }

    /// "Vaswani2017"; a second Vaswani 2017 becomes "Vaswani2017b" unless the entry
    /// already says "2017a".
    private static func authorYearLabel(for reference: Reference, index: Int, used: inout [String: Int]) -> String {
        guard let first = reference.authors.first, let surname = surname(of: first), let year = reference.year else {
            return "ref\(index + 1)"
        }
        let printed = regex("\(year)([a-z])\\b")
        if let letter = firstGroup(printed, reference.raw) { return "\(surname)\(year)\(letter)" }
        let base = "\(surname)\(year)"
        let seen = used[base, default: 0]
        used[base] = seen + 1
        guard seen > 0 else { return base }
        return base + String(Character(Unicode.Scalar(UInt8(97 + min(seen, 25)))))
    }

    static func surname(of author: String) -> String? {
        let family = author.contains(",") ? String(author[..<author.firstIndex(of: ",")!]) : author
        let word = family.split(separator: " ").last.map(String.init) ?? ""
        let letters = word.filter { $0.isLetter || $0 == "-" || $0 == "'" || $0 == "’" }
        return letters.isEmpty ? nil : letters
    }

    // MARK: Citations in running text

    /// Labels cited in a stretch of text, in order of appearance, without repeats.
    /// "[3, 7-9]" gives 3, 7, 8, 9; "(Vaswani et al., 2017; Bahdanau and Cho, 2015)" and
    /// "Vaswani et al. (2017)" give "Vaswani2017" and "Bahdanau2015".
    public static func citationLabels(in text: String) -> [String] {
        var found: [(position: Int, label: String)] = []
        let whole = NSRange(text.startIndex..., in: text)

        let numeric = regex(#"\[\s*(\d{1,3}(?:\s*[-–—]\s*\d{1,3})?(?:\s*[,;]\s*\d{1,3}(?:\s*[-–—]\s*\d{1,3})?)*)\s*\]"#)
        for match in numeric.matches(in: text, range: whole) {
            guard let range = Range(match.range(at: 1), in: text) else { continue }
            for (offset, part) in text[range].split(whereSeparator: { $0 == "," || $0 == ";" }).enumerated() {
                let ends = part.split(whereSeparator: { "-–—".contains($0) })
                    .compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
                guard let first = ends.first else { continue }
                // A "range" that runs backwards or spans hundreds is not a citation range.
                if ends.count == 2, ends[1] > first, ends[1] - first <= 60 {
                    for number in first...ends[1] { found.append((match.range.location * 100 + offset, String(number))) }
                } else {
                    found.append((match.range.location * 100 + offset, String(first)))
                }
            }
        }

        let etAl = "(?:\\s+(?:et\\s+al\\.?|(?:and|&)\\s+\(nameWord)))*"
        // Inside brackets: "Name et al., 2017" possibly with more years after it.
        let parenthetical = regex(#"\(([^()]*(?:18|19|20)\d{2}[a-z]?[^()]*)\)"#)
        let inside = regex("(\(nameWord))\(etAl),?\\s+(\(yearCore)[a-z]?)((?:\\s*,\\s*\(yearCore)[a-z]?)*)")
        for group in parenthetical.matches(in: text, range: whole) {
            let groupRange = group.range(at: 1)
            for match in inside.matches(in: text, range: groupRange) {
                guard let name = Range(match.range(at: 1), in: text), let year = Range(match.range(at: 2), in: text) else { continue }
                let position = match.range.location * 100
                found.append((position, "\(text[name])\(text[year])"))
                if let more = Range(match.range(at: 3), in: text) {
                    for (offset, extra) in text[more].split(separator: ",").enumerated() {
                        found.append((position + offset + 1, "\(text[name])\(extra.trimmingCharacters(in: .whitespaces))"))
                    }
                }
            }
        }
        // In the sentence: "Name et al. (2017)".
        let textual = regex("(\(nameWord))\(etAl)\\s+\\((\(yearCore)[a-z]?)(?:[,;][^)]*)?\\)")
        for match in textual.matches(in: text, range: whole) {
            guard let name = Range(match.range(at: 1), in: text), let year = Range(match.range(at: 2), in: text) else { continue }
            found.append((match.range.location * 100, "\(text[name])\(text[year])"))
        }

        var seen = Set<String>()
        return found.sorted { $0.position < $1.position }.map(\.label).filter { seen.insert($0).inserted }
    }

    // MARK: Regex helpers

    private static func regex(_ pattern: String, _ options: NSRegularExpression.Options = []) -> NSRegularExpression {
        // Patterns are literals in this file; a bad one is a programming error.
        try! NSRegularExpression(pattern: pattern, options: options)
    }

    private static func matches(_ pattern: NSRegularExpression, _ text: String) -> Bool {
        pattern.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }

    private static func firstGroup(_ pattern: NSRegularExpression, _ text: String) -> String? {
        allGroups(pattern, text).first
    }

    private static func allGroups(_ pattern: NSRegularExpression, _ text: String) -> [String] {
        pattern.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap {
            Range($0.range(at: 1), in: text).map { String(text[$0]) }
        }
    }
}
