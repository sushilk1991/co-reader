import Foundation

struct DocumentContextComposer {
    private let maxChunkCount = 5
    private let maxFocusChunkCount = 4
    private let maxSelectionChunkCount = 2
    private let chunkWordCount = 120
    private let chunkStepWordCount = 90

    func compose(
        title: String,
        question: String,
        scope: DocumentQueryScope,
        selection: DocumentSelection?,
        currentPageIndex: Int?,
        visiblePageIndexes: [Int],
        pageTexts: [String],
        unitLabel: String = "Page"
    ) -> DocumentContext {
        let effectiveScope = effectiveScope(for: scope, selection: selection)
        var sections: [String] = [
            "Context Scope",
            effectiveScope.contextHeading,
            ""
        ]

        if effectiveScope == .selection, let selection {
            sections.append("Selection Focus")
            sections.append(normalize(selection.text))
            sections.append("")
            sections.append("Nearby Context")
            sections.append(normalize(selection.surroundingText))
            sections.append("")
        }

        let chosenChunks = composeChunks(
            question: question,
            scope: effectiveScope,
            selection: selection,
            currentPageIndex: currentPageIndex,
            visiblePageIndexes: visiblePageIndexes,
            pageTexts: pageTexts
        )

        if !chosenChunks.isEmpty {
            sections.append("Coverage")
            sections.append(coverageSummary(for: chosenChunks, unitLabel: unitLabel))
            sections.append("")
            sections.append(effectiveScope == .document ? "Document Excerpts" : "Reading Context")
            sections.append("")
            sections.append(contentsOf: chosenChunks.flatMap { formattedLines(for: $0, unitLabel: unitLabel) })
        }

        if sections.count == 3 {
            sections.append("No extractable document context was found.")
        }

        return DocumentContext(title: title, excerpt: sections.joined(separator: "\n"))
    }

    private func effectiveScope(for scope: DocumentQueryScope, selection: DocumentSelection?) -> DocumentQueryScope {
        if scope == .selection, selection == nil {
            return .focus
        }

        return scope
    }

    private func composeChunks(
        question: String,
        scope: DocumentQueryScope,
        selection: DocumentSelection?,
        currentPageIndex: Int?,
        visiblePageIndexes: [Int],
        pageTexts: [String]
    ) -> [DocumentChunk] {
        switch scope {
        case .selection:
            if let selection {
                return rankedChunks(
                    for: [selection.pageIndex],
                    question: "\(selection.text) \(question)",
                    pageTexts: pageTexts,
                    limit: maxSelectionChunkCount
                )
            }

            return focusChunks(question: question, currentPageIndex: currentPageIndex, visiblePageIndexes: visiblePageIndexes, pageTexts: pageTexts)
        case .focus:
            return focusChunks(question: question, currentPageIndex: currentPageIndex, visiblePageIndexes: visiblePageIndexes, pageTexts: pageTexts)
        case .document:
            return retrieveRelevantChunks(
                question: question,
                pageTexts: pageTexts,
                limit: maxChunkCount,
                sampleAcrossDocumentWhenBroad: true
            )
        }
    }

    private func focusChunks(
        question: String,
        currentPageIndex: Int?,
        visiblePageIndexes: [Int],
        pageTexts: [String]
    ) -> [DocumentChunk] {
        if !visiblePageIndexes.isEmpty {
            return rankedChunks(for: visiblePageIndexes, question: question, pageTexts: pageTexts, limit: maxFocusChunkCount)
        }

        if let currentPageIndex {
            return rankedChunks(for: [currentPageIndex], question: question, pageTexts: pageTexts, limit: maxFocusChunkCount)
        }

        return retrieveRelevantChunks(
            question: question,
            pageTexts: pageTexts,
            limit: maxFocusChunkCount,
            sampleAcrossDocumentWhenBroad: false
        )
    }

    private func retrieveRelevantChunks(question: String, pageTexts: [String], limit: Int, sampleAcrossDocumentWhenBroad: Bool) -> [DocumentChunk] {
        let allChunks = pageTexts.enumerated().flatMap { pageIndex, text in
            chunks(for: pageIndex, text: text)
        }
        guard !allChunks.isEmpty else {
            return []
        }

        let keywords = keywords(from: question)

        if keywords.isEmpty {
            return sampleAcrossDocumentWhenBroad ? sampledChunks(from: allChunks, limit: limit) : Array(allChunks.prefix(limit))
        }

        let scoredChunks = allChunks.map { chunk in
            (chunk, score(text: chunk.text, keywords: keywords))
        }
        let matchingChunks = scoredChunks.filter { $0.1 > 0 }

        if matchingChunks.isEmpty {
            return sampleAcrossDocumentWhenBroad ? sampledChunks(from: allChunks, limit: limit) : Array(allChunks.prefix(limit))
        }

        var chunkCountByUnit: [Int: Int] = [:]
        var selectedChunks: [DocumentChunk] = []

        for (chunk, _) in matchingChunks.sorted(by: compareScoredChunks) {
            let unitIndex = chunk.pageRange.lowerBound
            if chunkCountByUnit[unitIndex, default: 0] >= 2 {
                continue
            }

            selectedChunks.append(chunk)
            chunkCountByUnit[unitIndex, default: 0] += 1

            if selectedChunks.count == limit {
                break
            }
        }

        return selectedChunks.sorted { lhs, rhs in
            lhs.pageRange.lowerBound < rhs.pageRange.lowerBound
        }
    }

    private func keywords(from question: String) -> [String] {
        let stopWords: Set<String> = [
            "the", "and", "that", "this", "with", "from", "into", "about",
            "summarize", "section", "explain", "please", "what", "does", "why",
            "whole", "document", "book", "chapter", "current", "reading", "focus",
            "selected", "passage", "guide", "study", "compact", "create", "short"
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
            partialResult += haystack.components(separatedBy: keyword).count - 1
        }
    }

    private func rankedChunks(for pageIndexes: [Int], question: String, pageTexts: [String], limit: Int) -> [DocumentChunk] {
        let uniquePageIndexes = Array(Set(pageIndexes)).sorted()
        let scopedChunks = uniquePageIndexes.flatMap { pageIndex in
            guard pageTexts.indices.contains(pageIndex) else {
                return [DocumentChunk]()
            }

            return chunks(for: pageIndex, text: pageTexts[pageIndex])
        }
        guard !scopedChunks.isEmpty else {
            return []
        }

        let keywords = keywords(from: question)
        if keywords.isEmpty {
            return Array(scopedChunks.prefix(limit))
        }

        let scoredChunks = scopedChunks.map { chunk in
            (chunk, score(text: chunk.text, keywords: keywords))
        }

        if scoredChunks.allSatisfy({ $0.1 == 0 }) {
            return Array(scopedChunks.prefix(limit))
        }

        return scoredChunks
            .sorted(by: compareScoredChunks)
            .prefix(limit)
            .map(\.0)
            .sorted { lhs, rhs in
                lhs.pageRange.lowerBound < rhs.pageRange.lowerBound
            }
    }

    private func chunks(for pageIndex: Int, text: String) -> [DocumentChunk] {
        let normalized = normalize(text)
        guard !normalized.isEmpty else {
            return []
        }

        let words = normalized.split(separator: " ")
        let pageNumber = pageIndex + 1
        if words.count <= chunkWordCount {
            return [DocumentChunk(pageRange: pageNumber...pageNumber, text: normalized)]
        }

        var result: [DocumentChunk] = []
        var lowerBound = 0
        while lowerBound < words.count {
            let upperBound = min(lowerBound + chunkWordCount, words.count)
            let excerpt = words[lowerBound ..< upperBound].joined(separator: " ")
            result.append(DocumentChunk(pageRange: pageNumber...pageNumber, text: excerpt))

            if upperBound == words.count {
                break
            }

            lowerBound += chunkStepWordCount
        }

        return result
    }

    private func sampledChunks(from allChunks: [DocumentChunk], limit: Int) -> [DocumentChunk] {
        let firstChunkPerUnit = Dictionary(grouping: allChunks, by: \.pageRange.lowerBound)
            .compactMap { _, chunks in
                chunks.first
            }
            .sorted { lhs, rhs in
                lhs.pageRange.lowerBound < rhs.pageRange.lowerBound
            }

        guard firstChunkPerUnit.count > limit else {
            return firstChunkPerUnit
        }

        let indexes = evenlySpacedIndexes(totalCount: firstChunkPerUnit.count, wantedCount: limit)
        return indexes.map { firstChunkPerUnit[$0] }
    }

    private func evenlySpacedIndexes(totalCount: Int, wantedCount: Int) -> [Int] {
        guard totalCount > 0, wantedCount > 0 else {
            return []
        }

        if totalCount <= wantedCount {
            return Array(0 ..< totalCount)
        }

        if wantedCount == 1 {
            return [0]
        }

        var indexes: [Int] = []
        for slot in 0 ..< wantedCount {
            let ratio = Double(slot) / Double(wantedCount - 1)
            let candidate = Int((ratio * Double(totalCount - 1)).rounded())
            if indexes.last != candidate {
                indexes.append(candidate)
            }
        }

        if indexes.count < wantedCount {
            for candidate in 0 ..< totalCount where !indexes.contains(candidate) {
                indexes.append(candidate)
                if indexes.count == wantedCount {
                    break
                }
            }
            indexes.sort()
        }

        return indexes
    }

    private func compareScoredChunks(lhs: (DocumentChunk, Int), rhs: (DocumentChunk, Int)) -> Bool {
        if lhs.1 == rhs.1 {
            return lhs.0.pageRange.lowerBound < rhs.0.pageRange.lowerBound
        }

        return lhs.1 > rhs.1
    }

    private func coverageSummary(for chunks: [DocumentChunk], unitLabel: String) -> String {
        let labels = Array(Set(chunks.map(\.pageRange.lowerBound))).sorted()
            .map { "\(unitLabel) \($0)" }
        return labels.joined(separator: ", ")
    }

    private func formattedLines(for chunk: DocumentChunk, unitLabel: String) -> [String] {
        [
            "[\(unitLabel) \(chunk.pageRange.lowerBound)]",
            String(chunk.text.prefix(900)),
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
