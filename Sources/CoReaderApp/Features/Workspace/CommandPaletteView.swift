import SwiftUI

struct CommandPaletteView: View {
    @Bindable var appModel: AppModel
    @State private var searchText = ""
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        ZStack {
            Color.black.opacity(0.25)
                .ignoresSafeArea()
                .onTapGesture {
                    appModel.isCommandPaletteVisible = false
                }

            VStack(spacing: 0) {
                searchBar

                Divider()
                    .background(ReaderTheme.lineSoft)

                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        if !searchText.isEmpty, appModel.selectedDocument != nil {
                            askAIRow
                        }

                        if appModel.selectedDocument != nil, !filteredAIActions.isEmpty {
                            paletteSection("AI Actions") {
                                ForEach(filteredAIActions) { action in
                                    paletteRow(
                                        title: action.title,
                                        icon: action.systemImage,
                                        shortcut: nil
                                    ) {
                                        appModel.isCommandPaletteVisible = false
                                        Task { await appModel.runQuickAction(action) }
                                    }
                                }
                            }
                        }

                        if !filteredNavigationCommands.isEmpty {
                            paletteSection("Navigate") {
                                ForEach(filteredNavigationCommands) { command in
                                    paletteRow(
                                        title: command.title,
                                        icon: command.icon,
                                        shortcut: command.shortcut
                                    ) {
                                        appModel.isCommandPaletteVisible = false
                                        command.action()
                                    }
                                }
                            }
                        }

                        if !filteredDocuments.isEmpty {
                            paletteSection("Documents") {
                                ForEach(filteredDocuments) { doc in
                                    paletteRow(
                                        title: doc.title,
                                        icon: doc.kind == .pdf ? "doc.richtext" : "book",
                                        shortcut: nil
                                    ) {
                                        appModel.isCommandPaletteVisible = false
                                        appModel.selectDocument(doc)
                                    }
                                }
                            }
                        }

                        if !appModel.autoConceptTags.isEmpty {
                            paletteSection("Current Concepts") {
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 6) {
                                        ForEach(appModel.autoConceptTags, id: \.self) { tag in
                                            Text(tag)
                                                .font(.caption.weight(.semibold))
                                                .foregroundStyle(ReaderTheme.teal)
                                                .padding(.horizontal, 8)
                                                .padding(.vertical, 4)
                                                .background(ReaderTheme.tealSoft, in: Capsule())
                                        }
                                    }
                                    .padding(.horizontal, 12)
                                }
                            }
                        }

                        if CoReaderPaths.isCloudSyncEnabled {
                            paletteSection("Status") {
                                HStack(spacing: 8) {
                                    Image(systemName: "icloud.fill")
                                        .font(.caption)
                                        .foregroundStyle(ReaderTheme.teal)
                                    Text("iCloud Drive sync active")
                                        .font(.caption)
                                        .foregroundStyle(ReaderTheme.smoke)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                            }
                        }
                    }
                    .padding(8)
                }
                .frame(maxHeight: 360)
            }
            .frame(width: 560)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(ReaderTheme.lineSoft.opacity(0.5), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.18), radius: 36, y: 16)
            .padding(.top, 80)
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .onAppear {
            isSearchFocused = true
        }
        .onExitCommand {
            appModel.isCommandPaletteVisible = false
        }
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "sparkle.magnifyingglass")
                .font(.title3)
                .foregroundStyle(ReaderTheme.teal)

            TextField("Ask, search, or jump to…", text: $searchText)
                .textFieldStyle(.plain)
                .font(.title3.weight(.medium))
                .foregroundStyle(ReaderTheme.ink)
                .focused($isSearchFocused)
                .onSubmit {
                    submitSearch()
                }

            Text("esc")
                .font(.caption.weight(.semibold).monospaced())
                .foregroundStyle(ReaderTheme.smoke)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(ReaderTheme.canvas, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    // MARK: - Ask AI Row

    private var askAIRow: some View {
        paletteRow(
            title: "Ask AI: \"\(searchText)\"",
            icon: "sparkles",
            shortcut: "↩"
        ) {
            submitSearch()
        }
    }

    // MARK: - Data

    private var filteredAIActions: [LearningAction] {
        guard searchText.isEmpty else {
            let query = searchText.lowercased()
            return LearningAction.allCases.filter { $0.title.lowercased().contains(query) }
        }
        return LearningAction.allCases
    }

    private var filteredDocuments: [ReaderDocument] {
        guard !searchText.isEmpty else {
            return appModel.importedDocuments
        }
        let query = searchText.lowercased()
        return appModel.importedDocuments.filter { $0.title.lowercased().contains(query) }
    }

    private var filteredNavigationCommands: [PaletteCommand] {
        let commands = navigationCommands
        guard !searchText.isEmpty else {
            return commands
        }
        let query = searchText.lowercased()
        return commands.filter { $0.title.lowercased().contains(query) }
    }

    private var navigationCommands: [PaletteCommand] {
        [
            PaletteCommand(
                title: "Import Document",
                icon: "plus.rectangle.on.folder",
                shortcut: nil,
                action: { appModel.beginDocumentImport() }
            ),
            PaletteCommand(
                title: appModel.isLibraryVisible ? "Hide Library" : "Show Library",
                icon: "sidebar.left",
                shortcut: "⌥⌘L",
                action: { appModel.toggleLibrary() }
            ),
            PaletteCommand(
                title: appModel.isInspectorVisible ? "Hide Tools" : "Show Tools",
                icon: "sidebar.right",
                shortcut: "⌥⌘I",
                action: { appModel.toggleInspector() }
            ),
            PaletteCommand(
                title: "Focus Chat",
                icon: "text.bubble",
                shortcut: nil,
                action: { appModel.focusChat() }
            ),
            PaletteCommand(
                title: "Refresh AI Providers",
                icon: "arrow.clockwise",
                shortcut: nil,
                action: { Task { await appModel.refreshProviders() } }
            )
        ]
    }

    // MARK: - Submit

    private func submitSearch() {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, appModel.selectedDocument != nil else { return }

        appModel.chatInput = trimmed
        appModel.isCommandPaletteVisible = false
        appModel.openInspector(tab: .ask)
        Task { await appModel.askQuestion() }
    }

    // MARK: - Components

    private func paletteSection(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(ReaderTheme.smoke)
                .textCase(.uppercase)
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, 4)

            content()
        }
    }

    private func paletteRow(
        title: String,
        icon: String,
        shortcut: String?,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.subheadline)
                    .foregroundStyle(ReaderTheme.teal)
                    .frame(width: 22, alignment: .center)

                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(ReaderTheme.ink)
                    .lineLimit(1)

                Spacer()

                if let shortcut {
                    Text(shortcut)
                        .font(.caption.monospaced())
                        .foregroundStyle(ReaderTheme.smoke)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(ReaderTheme.canvas, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Palette Command

private struct PaletteCommand: Identifiable {
    let id = UUID()
    let title: String
    let icon: String
    let shortcut: String?
    let action: @MainActor () -> Void
}
