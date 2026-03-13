import Observation
import SwiftUI

struct WorkspaceSidebarView: View {
    @Bindable var appModel: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(appModel.appTitle)
                    .font(.largeTitle.weight(.semibold))

                Text("AI-Powered PDF and EPUB Co-Reader")
                    .font(.title3)
                    .foregroundStyle(.secondary)

                Button("Import PDF or EPUB", systemImage: "plus.rectangle.on.folder", action: appModel.beginDocumentImport)
                    .buttonStyle(.borderedProminent)

                VStack(alignment: .leading, spacing: 8) {
                    Text(appModel.statusHeadline)
                        .font(.headline)

                    Text(appModel.statusDetail)
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 18))

                VStack(alignment: .leading, spacing: 14) {
                    ForEach(appModel.providerStatuses) { provider in
                        ProviderStatusCard(provider: provider)
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("Library")
                        .font(.headline)

                    if appModel.importedDocuments.isEmpty {
                        ContentUnavailableView(
                            "No documents yet",
                            systemImage: "tray",
                            description: Text("Import a PDF or EPUB to start the reading session.")
                        )
                    } else {
                        ForEach(appModel.importedDocuments) { document in
                            ImportedDocumentRow(
                                document: document,
                                isSelected: appModel.selectedDocument?.id == document.id,
                                action: { appModel.selectDocument(document) }
                            )
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
