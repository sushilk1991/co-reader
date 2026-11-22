import CoreaderKit
import SwiftUI

@main
struct CoreaderApp: App {
    @State private var app = AppModel()

    init() { DebugHooks.log("app init") }

    var body: some Scene {
        // A group, not a single Window: a single-window scene does not open when the app is
        // launched in the background. "New Window" is removed below, so there is only one.
        WindowGroup {
            RootView()
                .environment(app)
                .frame(minWidth: 940, minHeight: 620)
                .task {
                    DebugHooks.install { app.debug($0) }
                    await app.start()
                }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1320, height: 860)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    @MainActor weak var app: AppModel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        MainActor.assumeIsolated {
            DebugHooks.log("launched windows=\(NSApp.windows.map { "\($0.className) visible=\($0.isVisible)" })")
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                DebugHooks.log("later windows=\(NSApp.windows.map { "\($0.className) visible=\($0.isVisible) \($0.frame)" }) policy=\(NSApp.activationPolicy().rawValue)")
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated { app?.reader?.close() }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

struct RootView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        @Bindable var app = app
        let palette = app.palette
        ZStack {
            palette.surface.ignoresSafeArea()
            switch app.route {
            case .shelf:
                ShelfView()
                    .transition(.opacity)
            case .reader:
                if let reader = app.reader {
                    ReaderView(reader: reader)
                        .id(reader.entry.id)
                        .transition(.opacity.combined(with: .scale(scale: 0.985)))
                }
            }
            if let notice = app.notice {
                NoticeView(notice: notice)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, 44)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(10)
            }
        }
        .ignoresSafeArea()
        .environment(\.palette, palette)
        .preferredColorScheme(app.theme.isDark ? .dark : .light)
        .tint(palette.accent)
        .animation(.spring(duration: 0.35), value: app.notice)
        .onAppear { app.systemIsDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua }
        .onReceive(DistributedNotificationCenter.default().publisher(for: Notification.Name("AppleInterfaceThemeChangedNotification"))) { _ in
            // The app pins its own appearance, so ask the system directly.
            app.systemIsDark = UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark"
        }
        .sheet(item: $app.overlay) { overlay in
            Group {
                switch overlay {
                case .review: ReviewView()
                case .graph: GraphView()
                case .settings: SettingsView()
                case .addLink: AddLinkView()
                }
            }
            .environment(app)
            .environment(\.palette, palette)
            .preferredColorScheme(app.theme.isDark ? .dark : .light)
        }
        .sheet(item: $app.skillJob) { job in
            SkillBuilderView(job: job)
                .environment(app)
                .environment(\.palette, palette)
                .preferredColorScheme(app.theme.isDark ? .dark : .light)
        }
        .sheet(isPresented: Binding(get: { app.isLoaded && !app.hasOnboarded }, set: { if !$0 { app.hasOnboarded = true } })) {
            OnboardingView()
                .environment(app)
                .environment(\.palette, palette)
                .preferredColorScheme(app.theme.isDark ? .dark : .light)
                .interactiveDismissDisabled()
        }
        .confirmationDialog("Remove “\(app.confirmDelete?.book.title ?? "")” from your library?",
                            isPresented: Binding(get: { app.confirmDelete != nil }, set: { if !$0 { app.confirmDelete = nil } })) {
            Button("Move to Trash", role: .destructive) {
                if let entry = app.confirmDelete { app.delete(entry.id) }
                app.confirmDelete = nil
            }
            Button("Cancel", role: .cancel) { app.confirmDelete = nil }
        } message: {
            Text("The book, its notes and saved images move to the Trash together.")
        }
    }
}

private struct NoticeView: View {
    let notice: AppModel.Notice
    @Environment(\.palette) private var palette

    var body: some View {
        HStack(spacing: 8) {
            if notice.isError { Image(systemName: "exclamationmark.circle.fill").foregroundStyle(Color(hex: 0xE2725B)) }
            Text(notice.text).font(Typo.ui(12.5, weight: .medium)).foregroundStyle(palette.page).lineLimit(3)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(palette.ink.opacity(0.94), in: Capsule())
        .shadow(color: .black.opacity(0.2), radius: 12, y: 5)
        .frame(maxWidth: 560)
        .accessibilityAddTraits(.isStaticText)
    }
}
