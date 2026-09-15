import Observation
import SwiftUI

struct ReaderWorkspaceView: View {
    @Bindable var appModel: AppModel

    var body: some View {
        VStack(spacing: 14) {
            ReaderToolbarView(appModel: appModel)

            if let notice = appModel.sessionNotice {
                SessionNoticeBanner(message: notice, onDismiss: appModel.dismissSessionNotice)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            HStack(alignment: .top, spacing: 14) {
                if appModel.isLibraryVisible {
                    ReaderSidebarView(appModel: appModel)
                        .transition(.move(edge: .leading).combined(with: .opacity))
                }

                DocumentPreviewPanel(appModel: appModel)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                if appModel.isInspectorVisible {
                    ReaderInspectorView(appModel: appModel)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay {
            if appModel.isCommandPaletteVisible {
                CommandPaletteView(appModel: appModel)
                    .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .top)))
            }
        }
        .animation(.spring(response: 0.22, dampingFraction: 0.88), value: appModel.isCommandPaletteVisible)
        .background {
            ZStack {
                ReaderTheme.workspaceGradient

                RadialGradient(
                    colors: [
                        ReaderTheme.workspaceGlow.opacity(0.68),
                        ReaderTheme.workspaceGlow.opacity(0.0)
                    ],
                    center: .topLeading,
                    startRadius: 40,
                    endRadius: 700
                )
            }
        }
        .animation(.spring(response: 0.28, dampingFraction: 0.92), value: appModel.isLibraryVisible)
        .animation(.spring(response: 0.28, dampingFraction: 0.92), value: appModel.isInspectorVisible)
        .animation(.spring(response: 0.28, dampingFraction: 0.92), value: appModel.sessionNotice)
        .task {
            await appModel.restoreReadingStateIfNeeded()
            await appModel.refreshProvidersIfNeeded()
            try? appModel.refreshSavedNotes()
            await appModel.rebuildKnowledgeIndexIfNeeded()
        }
    }
}
