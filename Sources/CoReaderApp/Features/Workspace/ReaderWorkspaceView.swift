import Observation
import SwiftUI

struct ReaderWorkspaceView: View {
    @Bindable var appModel: AppModel

    var body: some View {
        VStack(spacing: 18) {
            ReaderToolbarView(appModel: appModel)

            HStack(alignment: .top, spacing: 18) {
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
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            LinearGradient(
                colors: [
                    ReaderTheme.canvas,
                    Color.white.opacity(0.96),
                    ReaderTheme.chrome.opacity(0.55)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .animation(.spring(response: 0.28, dampingFraction: 0.92), value: appModel.isLibraryVisible)
        .animation(.spring(response: 0.28, dampingFraction: 0.92), value: appModel.isInspectorVisible)
        .task {
            await appModel.refreshProvidersIfNeeded()
            try? appModel.refreshSavedNotes()
        }
    }
}
