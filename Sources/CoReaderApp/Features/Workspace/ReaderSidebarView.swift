import Observation
import SwiftUI

struct ReaderSidebarView: View {
    @Bindable var appModel: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 14) {
                    BrandMarkView(size: 52)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("CoReader")
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                            .foregroundStyle(ReaderTheme.ink)

                        Text("AI-powered PDF and EPUB co-reader")
                            .font(.subheadline)
                            .foregroundStyle(ReaderTheme.smoke)
                    }
                }

                Rectangle()
                    .fill(ReaderTheme.lineSoft)
                    .frame(height: 1)

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
                    .controlSize(.large)

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
                            appModel.isRestoringReadingState ? "Restoring your last session" : "No reading queue yet",
                            systemImage: "books.vertical",
                            description: Text(
                                appModel.isRestoringReadingState
                                    ? "Reading the saved library and positions."
                                    : "Import a PDF or EPUB to begin a focused session."
                            )
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

                if CoReaderPaths.isCloudSyncEnabled {
                    HStack(spacing: 8) {
                        Image(systemName: "icloud.fill")
                            .foregroundStyle(ReaderTheme.teal)
                        Text("iCloud Drive sync active")
                            .foregroundStyle(ReaderTheme.smoke)
                    }
                    .font(.caption)
                    .padding(.vertical, 8)
                }
            }
            .padding(20)
        }
        .frame(width: 300)
        .background(ReaderTheme.panelGradient, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(ReaderTheme.lineSoft, lineWidth: 1)
        )
        .shadow(color: ReaderTheme.shadow, radius: 18, y: 8)
    }
}
