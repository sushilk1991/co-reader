import Observation
import SwiftUI

struct ReaderSidebarView: View {
    @Bindable var appModel: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Library")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(ReaderTheme.ink)

                    Text("Open a document, jump back into recent reading, and confirm your local AI tools are live.")
                        .font(.subheadline)
                        .foregroundStyle(ReaderTheme.slate)
                }

                Button("Import PDF or EPUB", systemImage: "plus.rectangle.on.folder", action: appModel.beginDocumentImport)
                    .buttonStyle(.borderedProminent)
                    .tint(ReaderTheme.teal)

                VStack(alignment: .leading, spacing: 12) {
                    ForEach(appModel.importedDocuments) { document in
                        ImportedDocumentRow(
                            document: document,
                            isSelected: appModel.selectedDocument?.id == document.id,
                            action: { appModel.selectDocument(document) }
                        )
                    }

                    if appModel.importedDocuments.isEmpty {
                        ContentUnavailableView(
                            "No reading queue yet",
                            systemImage: "books.vertical",
                            description: Text("Import a PDF or EPUB to begin a focused session.")
                        )
                        .frame(maxWidth: .infinity)
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("Providers")
                        .font(.headline)
                        .foregroundStyle(ReaderTheme.ink)

                    ForEach(appModel.providerStatuses) { provider in
                        ProviderStatusCard(provider: provider)
                    }
                }
            }
            .padding(20)
        }
        .frame(width: 310)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(ReaderTheme.chromeStrong.opacity(0.7), lineWidth: 1)
        )
    }
}
