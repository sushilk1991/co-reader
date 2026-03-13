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
                    description: Text("Select text in the PDF, then save a highlight from the floating action bar.")
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
                                    Spacer()
                                    Text("Page \(highlight.pageIndex + 1)")
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
