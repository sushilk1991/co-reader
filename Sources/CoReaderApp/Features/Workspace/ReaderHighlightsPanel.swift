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
                            VStack(alignment: .leading, spacing: 10) {
                                HStack(spacing: 8) {
                                    Circle()
                                        .fill(highlight.color.swatchColor)
                                        .frame(width: 10, height: 10)

                                    Text(appModel.locationLabel(for: highlight.pageIndex))
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(ReaderTheme.brass)

                                    Spacer()

                                    Button {
                                        appModel.deleteHighlight(highlight.id)
                                    } label: {
                                        Image(systemName: "trash")
                                            .font(.caption)
                                            .foregroundStyle(ReaderTheme.rose)
                                    }
                                    .buttonStyle(.borderless)
                                }

                                Text(highlight.quotedText)
                                    .font(.callout)
                                    .foregroundStyle(ReaderTheme.ink)
                                    .lineLimit(5)

                                if let noteText = highlight.noteText {
                                    Text(noteText)
                                        .font(.footnote)
                                        .foregroundStyle(ReaderTheme.slate)
                                        .lineLimit(3)
                                }
                            }
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(ReaderTheme.paper, in: RoundedRectangle(cornerRadius: 16))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .stroke(ReaderTheme.lineSoft, lineWidth: 1)
                            )
                        }
                    }
                }
            }
        }
    }
}
