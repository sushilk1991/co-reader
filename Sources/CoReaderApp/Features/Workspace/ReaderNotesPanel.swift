import Observation
import SwiftUI

struct ReaderNotesPanel: View {
    @Bindable var appModel: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Notes")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(ReaderTheme.ink)

                Text("Write a portable note and anchor it to the current selection when one exists.")
                    .font(.subheadline)
                    .foregroundStyle(ReaderTheme.slate)
            }

            if let selectionSummary = appModel.selectionSummary {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Attached Selection")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(ReaderTheme.brass)

                    Text(selectionSummary)
                        .font(.callout)
                        .foregroundStyle(ReaderTheme.ink)
                }
                .padding(14)
                .background(ReaderTheme.canvas.opacity(0.75), in: RoundedRectangle(cornerRadius: 16))
            }

            TextEditor(text: $appModel.noteDraft)
                .font(.body)
                .padding(10)
                .frame(minHeight: 150)
                .scrollContentBackground(.hidden)
                .accessibilityLabel("Reader note draft")
                .background(Color.white.opacity(0.92), in: RoundedRectangle(cornerRadius: 18))
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(ReaderTheme.chromeStrong.opacity(0.8), lineWidth: 1)
                )

            HStack(spacing: 10) {
                Button("Save Note", systemImage: "square.and.arrow.down") {
                    do {
                        try appModel.saveNote()
                    } catch {
                        appModel.chatError = error.localizedDescription
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(ReaderTheme.brass)

                Button("Show Highlights", systemImage: "highlighter") {
                    appModel.showHighlights()
                }
                .buttonStyle(.bordered)
            }

            if appModel.savedNotes.isEmpty {
                ContentUnavailableView(
                    "No saved notes yet",
                    systemImage: "square.and.pencil",
                    description: Text("Saved notes stay local as Markdown and are indexed in the Brain.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(appModel.savedNotes, id: \.id) { note in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(note.title)
                                    .font(.headline)
                                    .foregroundStyle(ReaderTheme.ink)

                                if let excerpt = note.highlightExcerpt {
                                    Text(excerpt)
                                        .font(.callout)
                                        .foregroundStyle(ReaderTheme.slate)
                                        .lineLimit(3)
                                }

                                Text(note.fileURL.lastPathComponent)
                                    .font(.caption)
                                    .foregroundStyle(ReaderTheme.slate)
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
