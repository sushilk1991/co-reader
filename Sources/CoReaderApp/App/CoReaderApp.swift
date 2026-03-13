import SwiftUI

@main
struct CoReaderApp: App {
    @State private var appModel = AppModel()

    var body: some Scene {
        WindowGroup {
            ProviderStatusView(appModel: appModel)
                .frame(minWidth: 860, minHeight: 560)
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 980, height: 640)
    }
}
