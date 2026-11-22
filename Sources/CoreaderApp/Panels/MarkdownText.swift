import SwiftUI

/// Renders the Markdown an agent writes: paragraphs, headings, lists, quotes, code
/// fences, rules and simple tables. Inline styling goes through `AttributedString`.
struct MarkdownText: View {
    let text: String
    var baseSize: CGFloat = 13.5
    @Environment(\.palette) private var palette

    enum Block: Equatable {
        case paragraph(String)
        case heading(Int, String)
        case bullet(indent: Int, marker: String, text: String)
        case quote(String)
        case code(String)
        case rule
        case table([[String]])
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            ForEach(Array(Self.blocks(text).enumerated()), id: \.offset) { _, block in
                view(for: block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func view(for block: Block) -> some View {
        switch block {
        case .paragraph(let s):
            inline(s).font(Typo.ui(baseSize)).lineSpacing(3.5).foregroundStyle(palette.ink)
        case .heading(let level, let s):
            inline(s)
                .font(Typo.display(level <= 1 ? baseSize + 5 : (level == 2 ? baseSize + 3 : baseSize + 1), weight: .semibold))
                .foregroundStyle(palette.ink)
                .padding(.top, 4)
        case .bullet(let indent, let marker, let s):
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Text(marker)
                    .font(Typo.ui(baseSize).monospacedDigit())
                    .foregroundStyle(palette.tertiary)
                    .frame(minWidth: 12, alignment: .trailing)
                inline(s).font(Typo.ui(baseSize)).lineSpacing(3.5).foregroundStyle(palette.ink)
            }
            .padding(.leading, CGFloat(indent) * 16)
        case .quote(let s):
            inline(s)
                .font(Typo.serif(baseSize + 0.5, italic: true))
                .lineSpacing(3.5)
                .foregroundStyle(palette.secondary)
                .padding(.leading, 12)
                .overlay(alignment: .leading) { Rectangle().fill(palette.rule).frame(width: 2) }
        case .code(let s):
            ScrollView(.horizontal, showsIndicators: false) {
                Text(s)
                    .font(.system(size: baseSize - 1.5, design: .monospaced))
                    .foregroundStyle(palette.ink)
                    .textSelection(.enabled)
                    .padding(10)
            }
            .background(palette.ink.opacity(0.055), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        case .rule:
            Rectangle().fill(palette.rule).frame(height: 0.5).padding(.vertical, 2)
        case .table(let rows):
            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 6) {
                ForEach(Array(rows.enumerated()), id: \.offset) { r, row in
                    GridRow {
                        ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                            inline(cell)
                                .font(Typo.ui(baseSize - 1, weight: r == 0 ? .semibold : .regular))
                                .foregroundStyle(palette.ink)
                        }
                    }
                    if r == 0 { Rectangle().fill(palette.rule).frame(height: 0.5).gridCellColumns(max(row.count, 1)) }
                }
            }
        }
    }

    private func inline(_ s: String) -> Text {
        var options = AttributedString.MarkdownParsingOptions()
        options.interpretedSyntax = .inlineOnlyPreservingWhitespace
        guard var attributed = try? AttributedString(markdown: s, options: options) else { return Text(s) }
        for run in attributed.runs {
            if run.link != nil {
                attributed[run.range].foregroundColor = palette.accent
                attributed[run.range].underlineStyle = .init(pattern: .solid, color: nil)
            }
            if run.inlinePresentationIntent?.contains(.code) == true {
                attributed[run.range].font = .system(size: baseSize - 1, design: .monospaced)
                attributed[run.range].backgroundColor = palette.ink.opacity(0.06)
            }
        }
        return Text(attributed)
    }

    static func blocks(_ text: String) -> [Block] {
        var out: [Block] = []
        var paragraph: [String] = []
        var code: [String]?
        var quote: [String] = []
        var table: [[String]] = []

        func flush() {
            if !paragraph.isEmpty { out.append(.paragraph(paragraph.joined(separator: " "))); paragraph = [] }
            if !quote.isEmpty { out.append(.quote(quote.joined(separator: " "))); quote = [] }
            if !table.isEmpty { out.append(.table(table)); table = [] }
        }

        for raw in text.components(separatedBy: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("```") {
                if let lines = code { out.append(.code(lines.joined(separator: "\n"))); code = nil }
                else { flush(); code = [] }
                continue
            }
            if code != nil { code?.append(raw); continue }
            if line.isEmpty { flush(); continue }

            if line.hasPrefix("|"), line.hasSuffix("|"), line.count > 2 {
                if !paragraph.isEmpty || !quote.isEmpty { flush() }
                let cells = line.dropFirst().dropLast().split(separator: "|", omittingEmptySubsequences: false)
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                // The |---|---| separator row carries no content.
                if !cells.allSatisfy({ !$0.isEmpty && $0.allSatisfy { "-: ".contains($0) } }) { table.append(cells) }
                continue
            }
            if let match = line.firstMatch(of: /^(#{1,6})\s+(.*)$/) {
                flush()
                out.append(.heading(match.1.count, String(match.2)))
                continue
            }
            if line.allSatisfy({ $0 == "-" || $0 == "*" || $0 == "_" }), line.count >= 3 {
                flush()
                out.append(.rule)
                continue
            }
            if line.hasPrefix(">") {
                if !paragraph.isEmpty || !table.isEmpty { flush() }
                quote.append(String(line.dropFirst()).trimmingCharacters(in: .whitespaces))
                continue
            }
            let indent = raw.prefix { $0 == " " || $0 == "\t" }.reduce(0) { $0 + ($1 == "\t" ? 4 : 1) } / 2
            if let match = line.firstMatch(of: /^[-*+]\s+(.*)$/) {
                flush()
                out.append(.bullet(indent: min(indent, 4), marker: "•", text: String(match.1)))
                continue
            }
            if let match = line.firstMatch(of: /^(\d{1,3})[.)]\s+(.*)$/) {
                flush()
                out.append(.bullet(indent: min(indent, 4), marker: "\(match.1).", text: String(match.2)))
                continue
            }
            if !quote.isEmpty || !table.isEmpty { flush() }
            paragraph.append(line)
        }
        // An unterminated fence is normal while an answer is still streaming.
        if let lines = code { out.append(.code(lines.joined(separator: "\n"))) }
        flush()
        return out
    }
}
