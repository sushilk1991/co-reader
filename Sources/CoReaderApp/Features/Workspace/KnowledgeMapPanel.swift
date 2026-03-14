import SwiftUI

struct KnowledgeMapPanel: View {
    @Bindable var appModel: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Knowledge Map")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(ReaderTheme.ink)

                Text("Concepts, highlights, and notes from your reading.")
                    .font(.subheadline)
                    .foregroundStyle(ReaderTheme.slate)
            }

            if !appModel.allConceptTags.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Concepts")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(ReaderTheme.smoke)
                        .textCase(.uppercase)

                    ConceptFlowLayout(spacing: 6) {
                        ForEach(appModel.allConceptTags, id: \.self) { tag in
                            Text(tag)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(ReaderTheme.teal)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(ReaderTheme.tealSoft, in: Capsule())
                                .overlay(
                                    Capsule()
                                        .stroke(ReaderTheme.teal.opacity(0.3), lineWidth: 1)
                                )
                        }
                    }
                }
                .padding(14)
                .background(ReaderTheme.panelRaised.opacity(0.92), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }

            HStack(spacing: 16) {
                statBadge(count: appModel.savedNotes.filter { $0.kind == .note }.count, label: "Notes", icon: "square.and.pencil")
                statBadge(count: appModel.savedHighlights.count, label: "Highlights", icon: "highlighter")
                statBadge(count: appModel.allConceptTags.count, label: "Tags", icon: "tag")
            }

            if appModel.savedNotes.isEmpty && appModel.savedHighlights.isEmpty && appModel.allConceptTags.isEmpty {
                ContentUnavailableView(
                    "No knowledge yet",
                    systemImage: "brain",
                    description: Text("Ask AI questions, highlight text, or take notes to populate your knowledge map.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(appModel.savedNotes.prefix(30)), id: \.id) { note in
                            knowledgeCard(note)
                        }
                    }
                }
            }
        }
        .frame(maxHeight: .infinity, alignment: .topLeading)
    }

    private func statBadge(count: Int, label: String, icon: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundStyle(ReaderTheme.teal)
            Text("\(count)")
                .font(.headline.monospacedDigit())
                .foregroundStyle(ReaderTheme.ink)
            Text(label)
                .font(.caption2)
                .foregroundStyle(ReaderTheme.smoke)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(ReaderTheme.paper.opacity(0.92), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(ReaderTheme.lineSoft, lineWidth: 1)
        )
    }

    private func knowledgeCard(_ note: KnowledgeNoteSummary) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: noteIcon(for: note.kind))
                    .font(.caption)
                    .foregroundStyle(noteColor(for: note.kind))

                Text(note.kind.rawValue.capitalized)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(noteColor(for: note.kind))

                Spacer()

                if let pageIndex = note.pageIndex {
                    Text(appModel.locationLabel(for: pageIndex))
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(ReaderTheme.brass)
                }
            }

            if let excerpt = note.highlightExcerpt {
                Text(excerpt)
                    .font(.caption)
                    .foregroundStyle(ReaderTheme.ink)
                    .lineLimit(2)
            }

            if let preview = note.notePreview {
                Text(preview)
                    .font(.caption)
                    .foregroundStyle(ReaderTheme.slate)
                    .lineLimit(2)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ReaderTheme.paper, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(ReaderTheme.lineSoft, lineWidth: 1)
        )
    }

    private func noteIcon(for kind: KnowledgeNoteKind) -> String {
        switch kind {
        case .note:
            "square.and.pencil"
        case .highlight:
            "highlighter"
        case .aiChat:
            "sparkles"
        }
    }

    private func noteColor(for kind: KnowledgeNoteKind) -> Color {
        switch kind {
        case .note:
            ReaderTheme.brass
        case .highlight:
            ReaderTheme.teal
        case .aiChat:
            ReaderTheme.rose
        }
    }
}

// MARK: - Flow Layout

struct ConceptFlowLayout: Layout {
    let spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = computeRows(maxWidth: proposal.width ?? .infinity, subviews: subviews)
        var height: CGFloat = 0
        for (index, row) in rows.enumerated() {
            let rowHeight = row.map { $0.sizeThatFits(.unspecified).height }.max() ?? 0
            height += rowHeight
            if index < rows.count - 1 {
                height += spacing
            }
        }
        return CGSize(width: proposal.width ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = computeRows(maxWidth: bounds.width, subviews: subviews)
        var y = bounds.minY
        for row in rows {
            let rowHeight = row.map { $0.sizeThatFits(.unspecified).height }.max() ?? 0
            var x = bounds.minX
            for subview in row {
                let size = subview.sizeThatFits(.unspecified)
                subview.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
                x += size.width + spacing
            }
            y += rowHeight + spacing
        }
    }

    private func computeRows(maxWidth: CGFloat, subviews: Subviews) -> [[LayoutSubviews.Element]] {
        var rows: [[LayoutSubviews.Element]] = [[]]
        var currentWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentWidth + size.width > maxWidth, !rows[rows.count - 1].isEmpty {
                rows.append([])
                currentWidth = 0
            }
            rows[rows.count - 1].append(subview)
            currentWidth += size.width + spacing
        }

        return rows
    }
}
