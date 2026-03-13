import Observation
import SwiftUI

struct ReaderInspectorView: View {
    @Bindable var appModel: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Picker("Tool", selection: $appModel.selectedInspectorTab) {
                Text("Ask").tag(InspectorTab.ask)
                Text("Notes").tag(InspectorTab.notes)
                Text("Highlights").tag(InspectorTab.highlights)
                Text("Visuals").tag(InspectorTab.visuals)
            }
            .pickerStyle(.segmented)

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
        .frame(width: 380)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(ReaderTheme.chromeStrong.opacity(0.7), lineWidth: 1)
        )
    }
}
