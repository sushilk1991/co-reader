import Foundation

struct DocumentContextComposer {
    func compose(
        title: String,
        question: String,
        selection: DocumentSelection?,
        currentPageIndex: Int?,
        visiblePageIndexes: [Int],
        pageTexts: [String]
    ) -> DocumentContext {
        var sections: [String] = []

        if let selection {
            sections.append("Selection Focus")
            sections.append(selection.text)
            sections.append("")
            sections.append("Nearby Context")
            sections.append(selection.surroundingText)
            sections.append("")
        }

        let chosenChunks: [DocumentChunk]
        if !visiblePageIndexes.isEmpty {
            chosenChunks = chunks(for: visiblePageIndexes, in: pageTexts)
        } else if let currentPageIndex {
            chosenChunks = chunks(for: [currentPageIndex], in: pageTexts)
        } else {
            chosenChunks = retrieveRelevantChunks(question: question, pageTexts: pageTexts)
        }

        if !chosenChunks.isEmpty {
            sections.append(selection == nil ? "Relevant Sections" : "Reading Context")
            sections.append("")
            sections.append(contentsOf: chosenChunks.flatMap(formattedLines(for:)))
        }

        if sections.isEmpty {
            sections.append("No extractable document context was found.")
        }

        return DocumentContext(title: title, excerpt: sections.joined(separator: "\n"))
    }

    private func retrieveRelevantChunks(question: String, pageTexts: [String]) -> [DocumentChunk] {
        let keywords = keywords(from: question)
        let scoredPages = pageTexts.enumerated().map { index, text in
            (index, score(text: text, keywords: keywords))
        }

        let topPageIndexes = scoredPages
            .sorted { lhs, rhs in
                if lhs.1 == rhs.1 {
                    return lhs.0 < rhs.0
                }
                return lhs.1 > rhs.1
            }
            .prefix(3)
            .filter { $0.1 > 0 }
            .map(\.0)

        if topPageIndexes.isEmpty {
            return chunks(for: Array(pageTexts.indices.prefix(2)), in: pageTexts)
        }

        return chunks(for: topPageIndexes, in: pageTexts)
    }

    private func keywords(from question: String) -> [String] {
        let stopWords: Set<String> = [
            "the", "and", "that", "this", "with", "from", "into", "about",
            "summarize", "section", "explain", "please", "what", "does", "why"
        ]

        return question
            .lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
            .filter { $0.count > 2 && !stopWords.contains($0) }
    }

    private func score(text: String, keywords: [String]) -> Int {
        let haystack = text.lowercased()
        return keywords.reduce(into: 0) { partialResult, keyword in
            if haystack.contains(keyword) {
                partialResult += 1
            }
        }
    }

    private func chunks(for pageIndexes: [Int], in pageTexts: [String]) -> [DocumentChunk] {
        Array(Set(pageIndexes))
            .sorted()
            .compactMap { pageIndex in
                guard pageTexts.indices.contains(pageIndex) else {
                    return nil
                }

                let normalized = normalize(pageTexts[pageIndex])
                guard !normalized.isEmpty else {
                    return nil
                }

                let pageNumber = pageIndex + 1
                return DocumentChunk(pageRange: pageNumber...pageNumber, text: normalized)
            }
    }

    private func formattedLines(for chunk: DocumentChunk) -> [String] {
        [
            "[Page \(chunk.pageRange.lowerBound)]",
            String(chunk.text.prefix(1_600)),
            ""
        ]
    }

    private func normalize(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\u{0}", with: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
