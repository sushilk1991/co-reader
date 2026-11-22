import CoreaderKit
import SwiftUI

/// A map of your notes: books, the ideas that recur in them, and the passages in
/// different books that say similar things.
struct GraphView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss

    @State private var graph = NoteGraph()
    @State private var positions: [String: CGPoint] = [:]
    @State private var cards: [String: ReviewModel.Card] = [:]
    @State private var isBuilding = true
    @State private var hover: String?
    @State private var selected: String?

    var body: some View {
        HStack(spacing: 0) {
            ZStack {
                palette.surface
                if isBuilding {
                    VStack(spacing: 10) {
                        ProgressView().controlSize(.small)
                        Text("Connecting your notes…").font(Typo.ui(12)).foregroundStyle(palette.tertiary)
                    }
                } else if graph.nodes.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "point.3.connected.trianglepath.dotted").font(.system(size: 26, weight: .light)).foregroundStyle(palette.tertiary)
                        Text("No notes to connect yet").font(Typo.display(19)).foregroundStyle(palette.ink)
                        Text("Highlight across a few books and the ideas they share appear here.")
                            .font(Typo.ui(12.5)).foregroundStyle(palette.secondary)
                    }
                } else {
                    GeometryReader { geo in canvas(in: geo.size) }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Rectangle().fill(palette.rule).frame(width: 0.5)
            sidebar.frame(width: 320)
        }
        .frame(width: 1080, height: 680)
        .background(palette.page)
        .task { await build() }
    }

    // MARK: Canvas

    private func canvas(in size: CGSize) -> some View {
        let inset: CGFloat = 60
        func point(_ id: String) -> CGPoint? {
            positions[id].map { CGPoint(x: inset + $0.x * (size.width - inset * 2), y: inset + $0.y * (size.height - inset * 2)) }
        }
        let focus = selected ?? hover
        let neighbours: Set<String> = focus.map { f in
            Set(graph.edges.filter { $0.from == f || $0.to == f }.flatMap { [$0.from, $0.to] })
        } ?? []

        return ZStack {
            Canvas { context, _ in
                for edge in graph.edges {
                    guard let a = point(edge.from), let b = point(edge.to) else { continue }
                    let lit = focus != nil && (edge.from == focus || edge.to == focus)
                    var path = Path()
                    path.move(to: a)
                    path.addLine(to: b)
                    let base: Color = edge.kind == .similar ? palette.accent : palette.tertiary
                    let opacity = focus == nil ? (edge.kind == .similar ? 0.5 : 0.22) : (lit ? 0.8 : 0.06)
                    context.stroke(path, with: .color(base.opacity(opacity)),
                                   style: StrokeStyle(lineWidth: edge.kind == .similar ? 1.2 : 0.6, dash: edge.kind == .similar ? [4, 3] : []))
                }
            }
            ForEach(graph.nodes) { node in
                if let p = point(node.id) {
                    let dim = focus != nil && node.id != focus && !neighbours.contains(node.id)
                    nodeView(node)
                        .opacity(dim ? 0.2 : 1)
                        .position(p)
                        .onHover { inside in hover = inside ? node.id : (hover == node.id ? nil : hover) }
                        .onTapGesture { selected = selected == node.id ? nil : node.id }
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { selected = nil }
        .animation(.easeOut(duration: 0.15), value: focus)
    }

    @ViewBuilder
    private func nodeView(_ node: NoteGraph.Node) -> some View {
        switch node.kind {
        case .book:
            VStack(spacing: 5) {
                if let entry = app.entry(node.bookID ?? "") {
                    BookCover(entry: entry, width: 34)
                } else {
                    Circle().fill(palette.ink).frame(width: 16, height: 16)
                }
                Text(node.label).font(Typo.display(11, weight: .medium)).foregroundStyle(palette.ink)
                    .lineLimit(2).multilineTextAlignment(.center).frame(width: 110)
            }
        case .concept:
            Text(node.label)
                .font(Typo.ui(11, weight: .medium))
                .foregroundStyle(palette.accent)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(palette.page, in: Capsule())
                .overlay(Capsule().strokeBorder(palette.accent.opacity(0.5), lineWidth: 0.8))
        case .annotation:
            let color = cards[node.id]?.annotation.color.color ?? palette.tertiary
            Circle().fill(color).frame(width: 9, height: 9)
                .overlay(Circle().strokeBorder(.black.opacity(0.15), lineWidth: 0.5))
                .contentShape(Circle().inset(by: -5))
                .help(node.label)
        }
    }

    // MARK: Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Notes graph").font(Typo.display(17)).foregroundStyle(palette.ink)
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark").font(.system(size: 11, weight: .semibold)).foregroundStyle(palette.tertiary)
                        .frame(width: 26, height: 26).background(palette.ink.opacity(0.06), in: Circle())
                }
                .buttonStyle(.plain).keyboardShortcut(.cancelAction).accessibilityLabel("Close")
            }
            .padding(.horizontal, 20).padding(.top, 20)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if let id = selected ?? hover, let node = graph.nodes.first(where: { $0.id == id }) {
                        detail(for: node)
                    } else {
                        echoes
                    }
                }
                .padding(.horizontal, 20).padding(.vertical, 16)
            }
        }
        .background(palette.page)
    }

    /// Pairs of passages from different books that say similar things.
    private var echoes: some View {
        let pairs = graph.edges.filter { $0.kind == .similar }.sorted { $0.strength > $1.strength }.prefix(30)
        return VStack(alignment: .leading, spacing: 14) {
            Text("Echoes across books").labelStyle(palette)
            if pairs.isEmpty {
                Text(isBuilding ? " " : "When two books say something similar, the pair shows up here. Click any dot or idea on the map to explore.")
                    .font(Typo.ui(12.5)).foregroundStyle(palette.secondary).lineSpacing(3)
            }
            ForEach(Array(pairs.enumerated()), id: \.offset) { _, edge in
                if let a = cards[edge.from], let b = cards[edge.to] {
                    VStack(alignment: .leading, spacing: 8) {
                        passage(a)
                        Image(systemName: "arrow.up.arrow.down").font(.system(size: 9, weight: .semibold)).foregroundStyle(palette.accent)
                        passage(b)
                    }
                    .padding(12)
                    .background(palette.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .onHover { inside in hover = inside ? edge.from : nil }
                }
            }
        }
    }

    @ViewBuilder
    private func detail(for node: NoteGraph.Node) -> some View {
        let linked = graph.edges.filter { $0.from == node.id || $0.to == node.id }
            .map { $0.from == node.id ? $0.to : $0.from }
            .compactMap { cards[$0] }
        VStack(alignment: .leading, spacing: 12) {
            Text(node.kind == .concept ? "Idea" : (node.kind == .book ? "Book" : "Passage")).labelStyle(palette)
            if let card = cards[node.id] {
                passage(card)
            } else {
                Text(node.label).font(Typo.display(18)).foregroundStyle(palette.ink)
            }
            if !linked.isEmpty {
                Text(node.kind == .annotation ? "Connected passages" : "\(linked.count) passage\(linked.count == 1 ? "" : "s")").labelStyle(palette).padding(.top, 6)
                ForEach(linked.prefix(25)) { card in
                    passage(card)
                        .padding(10)
                        .background(palette.surface, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                }
            }
        }
    }

    private func passage(_ card: ReviewModel.Card) -> some View {
        Button {
            dismiss()
            app.open(card.entry.id, at: .annotation(bookID: card.entry.id, annotationID: card.id))
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(card.annotation.quote.isEmpty ? card.annotation.note : card.annotation.quote)
                    .font(Typo.serif(13))
                    .foregroundStyle(palette.ink)
                    .lineSpacing(2.5)
                    .lineLimit(5)
                    .multilineTextAlignment(.leading)
                Text(card.entry.book.title)
                    .font(Typo.ui(10.5, weight: .medium))
                    .foregroundStyle(palette.tertiary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Open in the book")
    }

    // MARK: Build

    private func build() async {
        let library = app.library, notes = app.notes
        struct Built: Sendable {
            var graph: NoteGraph
            var positions: [String: CGPoint]
            var cards: [String: ReviewModel.Card]
        }
        let built: Built? = try? await background {
            let all = try notes.all(in: library)
            var byBook: [String: (BookEntry, [Annotation])] = [:]
            var cards: [String: ReviewModel.Card] = [:]
            for pair in all where pair.annotation.kind != .image {
                byBook[pair.entry.id, default: (pair.entry, [])].1.append(pair.annotation)
                cards[pair.annotation.id] = .init(entry: pair.entry, annotation: pair.annotation)
            }
            let inputs = byBook.values.map { GraphInput(book: $0.0.book, annotations: $0.1) }
            let graph = GraphBuilder().build(from: inputs)
            let layout = GraphLayout.layout(graph).mapValues { CGPoint(x: $0.x, y: $0.y) }
            return Built(graph: graph, positions: layout, cards: cards)
        }
        if let built {
            graph = built.graph
            positions = built.positions
            cards = built.cards
        }
        isBuilding = false
    }
}
