import Observation
import SwiftUI

struct SelectionActionBar: View {
    @Bindable var appModel: AppModel

    var body: some View {
        if let selectionSummary = appModel.selectionSummary {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Selection")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(ReaderTheme.teal)
                    Spacer()
                    if let currentPageLabel = appModel.currentPageLabel {
                        Text(currentPageLabel)
                            .font(.caption)
                            .foregroundStyle(ReaderTheme.slate)
                    }
                }

                Text(selectionSummary)
                    .font(.body)
                    .foregroundStyle(ReaderTheme.ink)
                    .lineLimit(3)

                if appModel.supportsPersistentPDFHighlights {
                    Label(
                        appModel.isHighlightToolEnabled
                            ? "Drag again to lay down a persistent \(appModel.selectedHighlightColor.label.lowercased()) highlight."
                            : "Turn on the highlight pen in the toolbar to mark this passage directly on the PDF."
                        ,
                        systemImage: "highlighter"
                    )
                    .font(.caption)
                    .foregroundStyle(ReaderTheme.smoke)
                }

                HStack(spacing: 10) {
                    Button("Ask", systemImage: "sparkles") {
                        Task { await appModel.askAboutSelection() }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(ReaderTheme.teal)

                    if !appModel.supportsPersistentPDFHighlights {
                        Button("Highlight", systemImage: "highlighter") {
                            do {
                                try appModel.saveQuickHighlight()
                            } catch {
                                appModel.chatError = error.localizedDescription
                            }
                        }
                        .buttonStyle(.bordered)
                    }

                    Button("Note", systemImage: "square.and.pencil") {
                        appModel.prepareSelectionNote()
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(18)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(ReaderTheme.chromeStrong.opacity(0.75), lineWidth: 1)
            )
            .shadow(color: ReaderTheme.ink.opacity(0.08), radius: 18, y: 10)
        }
    }
}
