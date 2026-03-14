import SwiftUI

@main
struct CoReaderApp: App {
    @State private var appModel = AppModel()

    var body: some Scene {
        WindowGroup {
            ProviderStatusView(appModel: appModel)
                .frame(minWidth: 1120, minHeight: 760)
        }
        .defaultSize(width: 1320, height: 860)
        .commands {
            CommandGroup(after: .textEditing) {
                Button("Command Palette") {
                    appModel.isCommandPaletteVisible.toggle()
                }
                .keyboardShortcut("k", modifiers: .command)
            }
        }
    }
}
