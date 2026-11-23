import CoreaderKit
import SwiftUI

/// The connections card used by both onboarding and Settings.
struct ConnectionsList: View {
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var palette
    @State private var mastisk: Integrations.MastiskState?
    @State private var cliInstalled = Integrations.isCLIInstalled
    @State private var skillInstalled = Integrations.isSkillInstalled
    @State private var working = false

    var body: some View {
        VStack(spacing: 0) {
            row(symbol: "sparkles", title: "AI agents",
                detail: app.agents.isEmpty
                    ? (app.agentsChecked ? "None found. Install Claude Code, Codex or Antigravity to chat with your books." : "Looking…")
                    : "Found " + app.agents.map(\.kind.displayName).joined(separator: ", ") + ". No API keys needed.") {
                Button("Check again") {
                    Task {
                        app.agentsChecked = false
                        app.agents = await AgentDetector().detect()
                        app.agentsChecked = true
                        if app.preferredAgent == nil { app.preferredAgent = app.agents.first?.kind }
                    }
                }
            }
            divider
            row(symbol: "terminal", title: "Agent skill and command",
                detail: skillInstalled && cliInstalled
                    ? "Your agents can read your notes: ask one to “write a post from my notes on…”."
                    : "Installs the coreader command and a skill so Claude Code, Codex and others can search and use your notes.") {
                if skillInstalled && cliInstalled {
                    Label("Installed", systemImage: "checkmark").foregroundStyle(palette.tertiary).font(Typo.ui(12))
                } else {
                    Button("Install") {
                        do {
                            try Integrations.installCLI()
                            try Integrations.installSkill()
                            app.show("Installed. Agents pick it up in their next session.")
                        } catch {
                            app.show(error.localizedDescription, isError: true)
                        }
                        cliInstalled = Integrations.isCLIInstalled
                        skillInstalled = Integrations.isSkillInstalled
                    }
                }
            }
            divider
            row(symbol: "brain", title: "Mastisk", detail: mastiskDetail) {
                switch mastisk {
                case .disconnected:
                    Button("Connect") { toggleMastisk(true) }.disabled(working)
                case .connected:
                    Button("Disconnect") { toggleMastisk(false) }.disabled(working)
                case .none:
                    ProgressView().controlSize(.small)
                default:
                    EmptyView()
                }
            }
        }
        .background(palette.raised, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(palette.rule, lineWidth: 0.5))
        .task { mastisk = await Integrations.mastiskState() }
    }

    private var mastiskDetail: String {
        switch mastisk {
        case .none: "Checking…"
        case .notInstalled: "Not on this Mac. Coreader works on its own; your notes stay plain Markdown either way."
        case .needsConnector: "This version of Mastisk cannot read Coreader notes yet. Update Mastisk with the Coreader connector, then connect here."
        case .disconnected: "Mastisk can index your reading notes where they are. Nothing is copied, so there is one version of every note."
        case .connected(let books): "Connected. Mastisk reads \(books) book\(books == 1 ? "" : "s") of notes in place."
        case .remote: "Mastisk runs on another machine here, so it cannot read this library."
        case .unknown(let reason): reason
        }
    }

    private func toggleMastisk(_ connect: Bool) {
        working = true
        Task {
            mastisk = await Integrations.connectMastisk(connect)
            working = false
        }
    }

    private var divider: some View { Rectangle().fill(palette.rule.opacity(0.7)).frame(height: 0.5).padding(.leading, 50) }

    private func row<Trailing: View>(symbol: String, title: String, detail: String, @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol).font(.system(size: 15)).foregroundStyle(palette.accent).frame(width: 24).padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Typo.ui(13.5, weight: .semibold)).foregroundStyle(palette.ink)
                Text(detail).font(Typo.ui(12)).foregroundStyle(palette.secondary).lineSpacing(2).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            trailing().controlSize(.small)
        }
        .padding(14)
    }
}

/// Where the library lives.
struct LibraryLocationRow: View {
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var palette

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: isCloud ? "icloud" : "folder").font(.system(size: 15)).foregroundStyle(palette.accent).frame(width: 24).padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                Text(isCloud ? "Library in iCloud Drive" : "Library folder").font(Typo.ui(13.5, weight: .semibold)).foregroundStyle(palette.ink)
                Text(displayPath).font(Typo.ui(12)).foregroundStyle(palette.secondary).lineLimit(2).truncationMode(.middle)
                Text(isCloud ? "Books and notes sync to your other Apple devices through iCloud." : "Stored only on this Mac. Choose a folder in iCloud Drive to sync.")
                    .font(Typo.ui(11.5)).foregroundStyle(palette.tertiary)
            }
            Spacer(minLength: 12)
            Button("Change…") { choose() }.controlSize(.small)
        }
        .padding(14)
        .background(palette.raised, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(palette.rule, lineWidth: 0.5))
    }

    private var isCloud: Bool { app.library.root.path.contains("/Mobile Documents/") }

    private var displayPath: String {
        let path = app.library.root.path
        if let range = path.range(of: "/Mobile Documents/com~apple~CloudDocs/") { return "iCloud Drive / " + path[range.upperBound...] }
        return (path as NSString).abbreviatingWithTildeInPath
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.directoryURL = app.library.root.deletingLastPathComponent()
        panel.message = "Choose the folder that holds your Coreader library. Books already in the current folder stay there."
        panel.prompt = "Use This Folder"
        panel.begin { response in
            if response == .OK, let url = panel.url { Task { await app.useLibrary(at: url) } }
        }
    }
}

struct SettingsView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var app = app
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Settings").font(Typo.display(22)).foregroundStyle(palette.ink)
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark").font(.system(size: 11, weight: .semibold)).foregroundStyle(palette.tertiary)
                        .frame(width: 26, height: 26).background(palette.ink.opacity(0.06), in: Circle())
                }
                .buttonStyle(.plain).keyboardShortcut(.cancelAction).accessibilityLabel("Close")
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Library").labelStyle(palette).padding(.top, 18)
                    LibraryLocationRow()
                    Text("Connections").labelStyle(palette).padding(.top, 14)
                    ConnectionsList()
                    Text("Covers").labelStyle(palette).padding(.top, 14)
                    Toggle(isOn: $app.generatesCovers) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Design covers for papers and plain PDFs").frame(maxWidth: .infinity, alignment: .leading).font(Typo.ui(13.5, weight: .semibold)).foregroundStyle(palette.ink)
                            Text("Uses your agent's image generation. A drawn cover is used until it arrives, or when this is off.")
                                .font(Typo.ui(12)).foregroundStyle(palette.secondary)
                        }
                    }
                    .toggleStyle(.switch)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(palette.raised, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(palette.rule, lineWidth: 0.5))
                }
            }
        }
        .padding(26)
        .frame(width: 600, height: 620)
        .background(palette.page)
    }
}
