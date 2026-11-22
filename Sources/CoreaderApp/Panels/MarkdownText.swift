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

    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            ForEach(Array(Self.blocks(text).enumerated()), id: \.offset) { _, block in
                view(for: block)
                jumps(for: block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Links into a book, repeated as buttons under the passage that mentions them. A
    /// link inside running text is a small target (and unreachable from the keyboard);
    /// "go to this place" deserves a real control.
    @ViewBuilder
    private func jumps(for block: Block) -> some View {
        let source: String = switch block {
        case .paragraph(let s), .quote(let s), .heading(_, let s): s
        case .bullet(_, _, let s): s
        default: ""
        }
        let links = Self.bookLinks(in: source)
        if !links.isEmpty {
            FlowLayout(spacing: 6) {
                ForEach(Array(links.enumerated()), id: \.offset) { _, link in
                    Button { openURL(link.url) } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.turn.down.right").font(.system(size: 9, weight: .semibold))
                            Text(link.label).font(Typo.ui(baseSize - 2, weight: .medium)).lineLimit(1)
                        }
                        .foregroundStyle(palette.accent)
                        .padding(.horizontal, 8)
                        .frame(height: 22)
                        .background(palette.accent.opacity(0.10), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .help("Go to this place in the book")
                }
            }
        }
    }

    static func bookLinks(in text: String) -> [(label: String, url: URL)] {
        var out: [(String, URL)] = []
        // The target may contain one level of parentheses, as CFIs do.
        for match in text.matches(of: /\[([^\]]+)\]\((coreader:\/\/[^\s()]*(?:\([^()]*\)[^\s()]*)*)\)/) {
            let raw = String(match.2)
            let encoded = raw.replacingOccurrences(of: "[", with: "%5B").replacingOccurrences(of: "]", with: "%5D")
            if let url = URL(string: encoded), !out.contains(where: { $0.1 == url }) { out.append((String(match.1), url)) }
        }
        return out
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

/// Lays children out in rows, wrapping to the next row when one is full.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(subviews, width: proposal.width ?? .infinity)
        return CGSize(width: proposal.width ?? rows.width, height: rows.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (index, origin) in arrange(subviews, width: bounds.width).origins.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y),
                                  proposal: ProposedViewSize(width: min(bounds.width, subviews[index].sizeThatFits(.unspecified).width), height: nil))
        }
    }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> (origins: [CGPoint], width: CGFloat, height: CGFloat) {
        var origins: [CGPoint] = []
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, widest: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            let w = min(size.width, width)
            if x > 0, x + w > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            origins.append(CGPoint(x: x, y: y))
            x += w + spacing
            rowHeight = max(rowHeight, size.height)
            widest = max(widest, x - spacing)
        }
        return (origins, widest, y + rowHeight)
    }
}
