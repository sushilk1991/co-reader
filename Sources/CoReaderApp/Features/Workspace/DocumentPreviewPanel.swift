import SwiftUI

struct DocumentPreviewPanel: View {
    let document: ReaderDocument?

    var body: some View {
        Group {
            if let document {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(document.title)
                            .font(.title2.weight(.semibold))

                        Text(document.fileURL.path)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }

                    Group {
                        switch document.kind {
                        case .pdf:
                            PDFPreviewView(fileURL: document.fileURL)
                        case .epub:
                            ContentUnavailableView(
                                "EPUB imported",
                                systemImage: "books.vertical",
                                description: Text("The EPUB is in the workspace and ready for parsing. Native rendering is the next document-engine step.")
                            )
                        case .unknown:
                            ContentUnavailableView(
                                "Unsupported document",
                                systemImage: "questionmark.folder",
                                description: Text("This file was imported, but the current workspace only renders PDF previews.")
                            )
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.quaternary.opacity(0.2), in: RoundedRectangle(cornerRadius: 20))
                }
            } else {
                ContentUnavailableView(
                    "Import a document",
                    systemImage: "doc.badge.plus",
                    description: Text("Bring in a PDF or EPUB to start the reading workspace.")
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
