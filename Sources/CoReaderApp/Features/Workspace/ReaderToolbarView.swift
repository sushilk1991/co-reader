import Observation
import SwiftUI

struct ReaderToolbarView: View {
    @Bindable var appModel: AppModel

    var body: some View {
        HStack(spacing: 16) {
            Button {
                appModel.toggleLibrary()
            } label: {
                Label(appModel.isLibraryVisible ? "Hide Library" : "Show Library", systemImage: "sidebar.left")
            }
            .buttonStyle(.bordered)
            .keyboardShortcut("l", modifiers: [.command, .option])

            HStack(spacing: 12) {
                BrandMarkView(size: 42)

                VStack(alignment: .leading, spacing: 2) {
                    Text(appModel.selectedDocument?.title ?? "CoReader")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(ReaderTheme.ink)

                    Text(appModel.selectedDocument == nil ? "Reader-first local AI workspace" : "Read first. Ask only when needed.")
                        .font(.caption)
                        .foregroundStyle(ReaderTheme.slate)
                }
            }

            Spacer()

            if let currentPageLabel = appModel.currentPageLabel {
                Text(currentPageLabel)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(ReaderTheme.slate)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(ReaderTheme.chromeStrong.opacity(0.7), in: Capsule())
            }

            Label(appModel.providerReadinessLabel, systemImage: appModel.providerStatuses.contains(where: \.isAvailable) ? "bolt.circle.fill" : "bolt.slash")
                .font(.caption.weight(.semibold))
                .foregroundStyle(appModel.providerStatuses.contains(where: \.isAvailable) ? ReaderTheme.teal : ReaderTheme.rose)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial, in: Capsule())

            Button {
                appModel.toggleInspector(preferredTab: appModel.selectedInspectorTab)
            } label: {
                Label(appModel.isInspectorVisible ? "Hide Tools" : "Show Tools", systemImage: "sidebar.right")
            }
            .buttonStyle(.borderedProminent)
            .tint(ReaderTheme.teal)
            .keyboardShortcut("i", modifiers: [.command, .option])
        }
        .padding(18)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(ReaderTheme.chromeStrong.opacity(0.7), lineWidth: 1)
        )
    }
}
