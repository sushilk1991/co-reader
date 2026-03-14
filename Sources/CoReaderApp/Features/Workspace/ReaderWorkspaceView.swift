import Observation
import SwiftUI

struct ReaderWorkspaceView: View {
    @Bindable var appModel: AppModel

    var body: some View {
        VStack(spacing: 14) {
            ReaderToolbarView(appModel: appModel)

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
        .background {
            ZStack {
                ReaderTheme.workspaceGradient

                RadialGradient(
                    colors: [
                        Color.white.opacity(0.68),
                        Color.white.opacity(0.0)
                    ],
                    center: .topLeading,
                    startRadius: 40,
                    endRadius: 700
                )
            }
        }
        .animation(.spring(response: 0.28, dampingFraction: 0.92), value: appModel.isLibraryVisible)
        .animation(.spring(response: 0.28, dampingFraction: 0.92), value: appModel.isInspectorVisible)
        .task {
            await appModel.refreshProvidersIfNeeded()
            try? appModel.refreshSavedNotes()
        }
    }
}
