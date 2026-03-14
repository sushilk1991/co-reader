import Observation
import SwiftUI

struct ReaderInspectorView: View {
    @Bindable var appModel: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Workspace Tools")
                .font(.caption.weight(.semibold))
                .foregroundStyle(ReaderTheme.smoke)
                .textCase(.uppercase)

            Picker("Tool", selection: $appModel.selectedInspectorTab) {
                Text("Ask").tag(InspectorTab.ask)
                Text("Notes").tag(InspectorTab.notes)
                Text("Highlights").tag(InspectorTab.highlights)
                Text("Visuals").tag(InspectorTab.visuals)
            }
            .pickerStyle(.segmented)
            .padding(6)
            .background(ReaderTheme.paper.opacity(0.9), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

            Group {
                switch appModel.selectedInspectorTab {
                case .ask:
                    DocumentChatPanel(appModel: appModel)
                case .notes:
                    ReaderNotesPanel(appModel: appModel)
                case .highlights:
                    ReaderHighlightsPanel(appModel: appModel)
                case .visuals:
                    ReaderVisualsPanel(appModel: appModel)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(20)
        .frame(width: 368)
        .background(ReaderTheme.panelGradient, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(ReaderTheme.lineSoft, lineWidth: 1)
        )
        .shadow(color: ReaderTheme.shadow, radius: 18, y: 8)
    }
}
