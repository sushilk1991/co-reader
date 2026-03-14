import Observation
import SwiftUI

struct ReaderHighlightsPanel: View {
    @Bindable var appModel: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Highlights")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(ReaderTheme.ink)

                Text("Capture the exact passage you want to remember, then come back through the Brain later.")
                    .font(.subheadline)
                    .foregroundStyle(ReaderTheme.slate)
            }

            if appModel.savedHighlights.isEmpty {
                ContentUnavailableView(
                    "No highlights yet",
                    systemImage: "highlighter",
                    description: Text(
                        appModel.supportsPersistentPDFHighlights
                            ? "Turn on the highlight pen in the toolbar, drag across text to keep it on the PDF, then right-click or use Delete here to remove it."
                            : "Select text in the document, then save a highlight from the action bar."
                    )
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(appModel.savedHighlights) { highlight in
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text(highlight.documentTitle)
                                        .font(.headline)
                                        .foregroundStyle(ReaderTheme.ink)

                                    Text(highlight.color.label)
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(ReaderTheme.ink)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .background(highlight.color.pillColor, in: Capsule())

                                    Spacer()

                                    Button("Delete", systemImage: "trash") {
                                        appModel.deleteHighlight(highlight.id)
                                    }
                                    .buttonStyle(.borderless)
                                    .foregroundStyle(ReaderTheme.rose)

                                    Text(appModel.locationLabel(for: highlight.pageIndex))
                                        .font(.caption.weight(.medium))
                                        .foregroundStyle(ReaderTheme.brass)
                                }

                                Text(highlight.quotedText)
                                    .font(.callout)
                                    .foregroundStyle(ReaderTheme.slate)

                                if let noteText = highlight.noteText {
                                    Text(noteText)
                                        .font(.footnote)
                                        .foregroundStyle(ReaderTheme.ink)
                                }
                            }
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.white.opacity(0.86), in: RoundedRectangle(cornerRadius: 16))
                        }
                    }
                }
            }
        }
    }
}
