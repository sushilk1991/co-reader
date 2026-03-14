import Observation
import SwiftUI

struct DocumentPreviewPanel: View {
    @Bindable var appModel: AppModel

    var body: some View {
        Group {
            if let document = appModel.selectedDocument {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(document.title)
                            .font(.title.weight(.bold))
                            .foregroundStyle(ReaderTheme.ink)

                        HStack(spacing: 12) {
                            Text(document.fileURL.path)
                                .font(.caption)
                                .foregroundStyle(ReaderTheme.slate)
                                .textSelection(.enabled)

                            if let currentPageLabel = appModel.currentPageLabel {
                                Text(currentPageLabel)
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(ReaderTheme.brass)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(ReaderTheme.canvas.opacity(0.9), in: Capsule())
                            }
                        }
                    }

                    ZStack(alignment: .bottomLeading) {
                        Group {
                            switch document.kind {
                            case .pdf:
                                PDFPreviewView(
                                    fileURL: document.fileURL,
                                    onSelectionChange: { selection in
                                        appModel.updateCurrentSelection(selection)
                                    },
                                    onReadingPositionChange: { currentPageIndex, visiblePageIndexes in
                                        appModel.updateReadingPosition(
                                            currentPageIndex: currentPageIndex,
                                            visiblePageIndexes: visiblePageIndexes
                                        )
                                    }
                                )
                            case .epub:
                                EPUBPreviewView(
                                    fileURL: document.fileURL,
                                    onSelectionChange: { selection in
                                        appModel.updateCurrentSelection(selection)
                                    },
                                    onReadingPositionChange: { currentSectionIndex, visibleSectionIndexes in
                                        appModel.updateReadingPosition(
                                            currentPageIndex: currentSectionIndex,
                                            visiblePageIndexes: visibleSectionIndexes
                                        )
                                    }
                                )
                            case .unknown:
                                ContentUnavailableView(
                                    "Unsupported document",
                                    systemImage: "questionmark.folder",
                                    description: Text("This file was imported, but the current workspace can only render PDF and EPUB documents right now.")
                                )
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.white.opacity(0.96), in: RoundedRectangle(cornerRadius: 28, style: .continuous))

                        if appModel.hasActiveSelection {
                            SelectionActionBar(appModel: appModel)
                                .padding(20)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                VStack(alignment: .leading, spacing: 20) {
                    Spacer()

                    Label("Read First, Ask Second", systemImage: "book.pages")
                        .font(.title.weight(.bold))
                        .foregroundStyle(ReaderTheme.ink)

                    Text("Import a PDF or EPUB and the workspace will stay out of the way until you need AI, notes, or highlights.")
                        .font(.title3)
                        .foregroundStyle(ReaderTheme.slate)
                        .frame(maxWidth: 520, alignment: .leading)

                    Button("Import PDF or EPUB", systemImage: "plus.rectangle.on.folder", action: appModel.beginDocumentImport)
                        .buttonStyle(.borderedProminent)
                        .tint(ReaderTheme.teal)

                    Spacer()
                }
                .padding(40)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .background(
                    LinearGradient(
                        colors: [Color.white.opacity(0.92), ReaderTheme.canvas.opacity(0.92)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    in: RoundedRectangle(cornerRadius: 32, style: .continuous)
                )
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
