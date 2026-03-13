import Observation
import SwiftUI
import UniformTypeIdentifiers

struct ProviderStatusView: View {
    @Bindable var appModel: AppModel

    private let supportedDocumentTypes = [UTType.pdf, UTType(filenameExtension: "epub")].compactMap { $0 }

    var body: some View {
        HStack(spacing: 24) {
            WorkspaceSidebarView(appModel: appModel)
                .frame(width: 340)

            DocumentPreviewPanel(document: appModel.selectedDocument)
        }
        .padding(24)
        .task {
            await appModel.refreshProvidersIfNeeded()
        }
        .fileImporter(
            isPresented: $appModel.isImportingDocument,
            allowedContentTypes: supportedDocumentTypes,
            allowsMultipleSelection: false
        ) { result in
            guard case let .success(urls) = result, let url = urls.first else {
                return
            }

            appModel.importDocument(from: url)
        }
    }
}

#Preview {
    ProviderStatusView(appModel: AppModel())
        .frame(width: 980, height: 640)
}
