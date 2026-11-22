import CoreaderKit
import SwiftUI

@main
struct CoreaderApp: App {
    var body: some Scene {
        WindowGroup {
            HarnessView()
                .frame(minWidth: 900, minHeight: 600)
        }
    }
}

/// Temporary: proves the web reader renders a book.
struct HarnessView: View {
    @State private var controller = WebReaderController()
    @State private var status = "loading"

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            ReaderTheme.paper.palette.page.ignoresSafeArea()
            WebReaderView(controller: controller)
            Text(status).font(.caption).padding(6)
        }
        .onAppear {
            DebugHooks.install { _ in }
            controller.onEvent = { event in
                switch event {
                case .opened(let o): status = "opened: \(o.title) — \(o.authors.joined(separator: ", ")) toc=\(o.toc.count) cover=\(o.cover?.count ?? 0)"
                case .openFailed(let m): status = "FAILED: \(m)"
                case .relocated(let r): status = "at \(r.fraction) \(r.chapter)"
                default: break
                }
                DebugHooks.log(status)
            }
            if let path = ProcessInfo.processInfo.environment["COREADER_OPEN"] {
                controller.open(file: URL(fileURLWithPath: path), lastCFI: nil, marks: [],
                                settings: ReaderSettings().webPayload(theme: .paper))
            }
        }
    }
}
