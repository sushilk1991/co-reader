import Observation
import PDFKit
import SwiftUI

struct DocumentPreviewPanel: View {
    @Bindable var appModel: AppModel

    var body: some View {
        Group {
            if let document = appModel.selectedDocument {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(alignment: .top, spacing: 16) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(document.title)
                                .font(.system(size: 31, weight: .bold, design: .rounded))
                                .foregroundStyle(ReaderTheme.ink)

                            Text(document.fileURL.lastPathComponent)
                                .font(.caption)
                                .foregroundStyle(ReaderTheme.smoke)
                                .textSelection(.enabled)
                        }

                        Spacer()

                        HStack(spacing: 10) {
                            Text(document.kind.displayName)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(ReaderTheme.teal)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(ReaderTheme.tealSoft, in: Capsule())
                                .overlay(
                                    Capsule()
                                        .stroke(ReaderTheme.lineSoft, lineWidth: 1)
                                )

                            if let currentPageLabel = appModel.currentPageLabel {
                                Text(currentPageLabel)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(ReaderTheme.brass)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(ReaderTheme.brassSoft, in: Capsule())
                                    .overlay(
                                        Capsule()
                                            .stroke(ReaderTheme.lineSoft, lineWidth: 1)
                                    )
                            }
                        }
                    }

                    if appModel.readingProgress > 0 {
                        ReadingProgressBar(progress: appModel.readingProgress)
                            .padding(.horizontal, 4)
                    }

                    ZStack(alignment: .bottomLeading) {
                        Group {
                            switch document.kind {
                            case .pdf:
                                PDFPreviewView(
                                    fileURL: document.fileURL,
                                    highlights: appModel.pdfDocumentHighlights,
                                    isHighlightToolEnabled: appModel.isHighlightToolEnabled,
                                    selectedHighlightColor: appModel.selectedHighlightColor,
                                    onSelectionChange: { selection in
                                        appModel.updateCurrentSelection(selection)
                                    },
                                    onReadingPositionChange: { currentPageIndex, visiblePageIndexes in
                                        appModel.updateReadingPosition(
                                            currentPageIndex: currentPageIndex,
                                            visiblePageIndexes: visiblePageIndexes
                                        )
                                    },
                                    onHighlightCapture: { drafts in
                                        appModel.capturePDFHighlights(drafts)
                                    },
                                    onHighlightRemoval: { highlightID in
                                        appModel.deleteHighlight(highlightID)
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
                        .background(ReaderTheme.paper, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 28, style: .continuous)
                                .stroke(ReaderTheme.lineSoft, lineWidth: 1)
                        )

                        VStack(alignment: .leading, spacing: 12) {
                            if let summary = appModel.autoSummary {
                                PageSummaryCard(summary: summary)
                                    .transition(.move(edge: .bottom).combined(with: .opacity))
                            }

                            if appModel.hasActiveSelection {
                                SelectionActionBar(appModel: appModel)
                            }
                        }
                        .padding(20)
                        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: appModel.autoSummary != nil)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .padding(22)
                .background(ReaderTheme.paperGradient, in: RoundedRectangle(cornerRadius: 32, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 32, style: .continuous)
                        .stroke(ReaderTheme.lineSoft, lineWidth: 1)
                )
                .shadow(color: ReaderTheme.shadow.opacity(0.8), radius: 24, y: 12)
            } else {
                VStack(alignment: .leading, spacing: 20) {
                    Spacer()

                    BrandMarkView(size: 88)

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
                    ReaderTheme.paperGradient,
                    in: RoundedRectangle(cornerRadius: 32, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 32, style: .continuous)
                        .stroke(ReaderTheme.lineSoft, lineWidth: 1)
                )
            }
        }
        .padding(4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task(id: appModel.selectedDocument?.id) {
            guard let document = appModel.selectedDocument else { return }
            switch document.kind {
            case .pdf:
                if let pdfDoc = PDFKit.PDFDocument(url: document.fileURL) {
                    appModel.updateTotalPages(pdfDoc.pageCount)
                }
            case .epub:
                if let book = try? LiveEPUBBookLoader().loadBook(from: document.fileURL) {
                    appModel.updateTotalPages(book.sections.count)
                }
            case .unknown:
                break
            }
        }
    }
}
