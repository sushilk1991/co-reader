import CoreaderKit
import SwiftUI

/// The update sheet: what is new, and one button to get it.
struct UpdateView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var palette

    var body: some View {
        let updater = app.updater
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 16) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable().frame(width: 56, height: 56)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title(updater.phase)).font(Typo.display(20)).foregroundStyle(palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(subtitle(updater)).font(Typo.ui(12.5)).foregroundStyle(palette.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            switch updater.phase {
            case .available(let release):
                notes(release)
                HStack(spacing: 10) {
                    Button("Skip This Version") { updater.skip(release) }
                    Spacer()
                    Button("Later") { updater.dismiss() }.keyboardShortcut(.cancelAction)
                    Button("Update and Relaunch") { updater.install(release) }.keyboardShortcut(.defaultAction)
                }
                .padding(.top, 20)
            case .downloading(_, let fraction):
                ProgressView(value: fraction).tint(palette.accent).padding(.top, 22)
                HStack {
                    Spacer()
                    Button("Cancel") { updater.cancel() }.keyboardShortcut(.cancelAction)
                }
                .padding(.top, 16)
            case .installing, .checking:
                ProgressView().controlSize(.small).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 22)
                HStack { Spacer(); Button("Cancel") { updater.cancel() }.keyboardShortcut(.cancelAction) }.padding(.top, 16)
            case .relaunching:
                ProgressView().controlSize(.small).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 22)
            case .installedOnDisk:
                HStack(spacing: 10) {
                    Spacer()
                    Button("Later") { updater.dismiss() }.keyboardShortcut(.cancelAction)
                    Button("Relaunch Now") { updater.relaunch() }.keyboardShortcut(.defaultAction)
                }
                .padding(.top, 20)
            case .failed(_, let page):
                HStack(spacing: 10) {
                    Spacer()
                    if let page { Button("Open Download Page") { NSWorkspace.shared.open(page); updater.dismiss() } }
                    Button("OK") { updater.dismiss() }.keyboardShortcut(.defaultAction)
                }
                .padding(.top, 20)
            case .upToDate, .idle:
                HStack { Spacer(); Button("OK") { updater.dismiss() }.keyboardShortcut(.defaultAction) }.padding(.top, 20)
            }
        }
        .padding(26)
        .frame(width: 500)
        .background(palette.page)
        .interactiveDismissDisabled()
    }

    private func title(_ phase: Updater.Phase) -> String {
        switch phase {
        case .idle, .checking: "Checking for updates…"
        case .upToDate: "Coreader is up to date"
        case .available(let release): "Coreader \(release.version) is available"
        case .downloading(let release, _): "Downloading Coreader \(release.version)…"
        case .installing(let release): "Installing Coreader \(release.version)…"
        case .relaunching(let version): "Restarting as Coreader \(version)…"
        case .installedOnDisk(let version): "Coreader \(version) is installed"
        case .failed: "The update did not go through"
        }
    }

    private func subtitle(_ updater: Updater) -> String {
        let current = updater.currentVersion?.description ?? "this version"
        switch updater.phase {
        case .idle, .checking: return "You have \(current)."
        case .upToDate: return "\(current) is the newest version."
        case .available: return "You have \(current). Your library and notes are not touched by an update."
        case .downloading(let release, let fraction):
            let total = Double(release.size)
            guard total > 0 else { return "\(Int(fraction * 100))%" }
            let style = ByteCountFormatStyle(style: .file)
            return "\(Int64(total * fraction).formatted(style)) of \(Int64(total).formatted(style))"
        case .installing: return "Checking the download, then Coreader will reopen."
        case .relaunching: return "Saving your place. Coreader will open again in a moment."
        case .installedOnDisk: return "This window is still the older \(current). Relaunch to start using the new version."
        case .failed(let message, _): return message
        }
    }

    @ViewBuilder private func notes(_ release: AppRelease) -> some View {
        if !release.notes.isEmpty {
            Text("What's new").labelStyle(palette).padding(.top, 22)
            ScrollView {
                // Release notes are short Markdown; inline styles and line breaks are enough.
                Text((try? AttributedString(markdown: release.notes, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(release.notes))
                    .font(Typo.ui(13)).lineSpacing(3).foregroundStyle(palette.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(14)
            }
            .frame(maxHeight: 190)
            .background(palette.raised, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(palette.rule, lineWidth: 0.5))
            .padding(.top, 8)
        }
    }
}
