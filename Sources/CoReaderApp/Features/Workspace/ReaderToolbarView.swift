import Observation
import SwiftUI

struct ReaderToolbarView: View {
    @Bindable var appModel: AppModel

    var body: some View {
        HStack(spacing: 14) {
            Button {
                appModel.toggleLibrary()
            } label: {
                Label(appModel.isLibraryVisible ? "Hide Library" : "Show Library", systemImage: "sidebar.left")
            }
            .buttonStyle(.plain)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(ReaderTheme.ink)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(ReaderTheme.paper.opacity(0.94), in: Capsule())
            .overlay(
                Capsule()
                    .stroke(ReaderTheme.lineSoft, lineWidth: 1)
            )
            .keyboardShortcut("l", modifiers: [.command, .option])

            HStack(spacing: 12) {
                BrandMarkView(size: 38)

                VStack(alignment: .leading, spacing: 2) {
                    Text("CoReader")
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .foregroundStyle(ReaderTheme.ink)

                    Text(appModel.selectedDocument?.title ?? "Reader-first local AI workspace")
                        .font(.caption)
                        .foregroundStyle(ReaderTheme.smoke)
                        .lineLimit(1)
                }
            }

            Spacer()

            if let currentPageLabel = appModel.currentPageLabel {
                Text(currentPageLabel)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(ReaderTheme.brass)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(ReaderTheme.brassSoft, in: Capsule())
                    .overlay(
                        Capsule()
                            .stroke(ReaderTheme.lineSoft, lineWidth: 1)
                    )
            }

            if appModel.supportsPersistentPDFHighlights {
                HStack(spacing: 8) {
                    Button {
                        appModel.toggleHighlightTool()
                    } label: {
                        Label(appModel.isHighlightToolEnabled ? "Highlight On" : "Highlight", systemImage: "highlighter")
                    }
                    .buttonStyle(.plain)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(appModel.isHighlightToolEnabled ? ReaderTheme.ink : ReaderTheme.smoke)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        appModel.isHighlightToolEnabled ? appModel.selectedHighlightColor.pillColor : ReaderTheme.paper,
                        in: Capsule()
                    )
                    .overlay(
                        Capsule()
                            .stroke(ReaderTheme.lineSoft, lineWidth: 1)
                    )

                    Menu {
                        ForEach(ReaderHighlightColor.allCases, id: \.self) { color in
                            Button {
                                appModel.setHighlightColor(color)
                            } label: {
                                Label(color.label, systemImage: color == appModel.selectedHighlightColor ? "checkmark.circle.fill" : "circle")
                            }
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(appModel.selectedHighlightColor.swatchColor)
                                .frame(width: 10, height: 10)
                            Text(appModel.selectedHighlightColor.label)
                                .font(.caption.weight(.semibold))
                        }
                        .foregroundStyle(ReaderTheme.ink)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(ReaderTheme.paper.opacity(0.96), in: Capsule())
                        .overlay(
                            Capsule()
                                .stroke(ReaderTheme.lineSoft, lineWidth: 1)
                        )
                    }
                    .menuStyle(.borderlessButton)
                }
            }

            Button {
                appModel.isCommandPaletteVisible.toggle()
            } label: {
                Label("⌘K", systemImage: "command")
            }
            .buttonStyle(.plain)
            .font(.caption.weight(.semibold))
            .foregroundStyle(ReaderTheme.smoke)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(ReaderTheme.paper.opacity(0.94), in: Capsule())
            .overlay(
                Capsule()
                    .stroke(ReaderTheme.lineSoft, lineWidth: 1)
            )

            Label(appModel.providerReadinessLabel, systemImage: appModel.providerStatuses.contains(where: \.isAvailable) ? "bolt.circle.fill" : "bolt.slash")
                .font(.caption.weight(.semibold))
                .foregroundStyle(appModel.providerStatuses.contains(where: \.isAvailable) ? ReaderTheme.teal : ReaderTheme.rose)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    appModel.providerStatuses.contains(where: \.isAvailable) ? ReaderTheme.tealSoft : ReaderTheme.roseSoft,
                    in: Capsule()
                )
                .overlay(
                    Capsule()
                        .stroke(ReaderTheme.lineSoft, lineWidth: 1)
                )

            Button {
                appModel.toggleInspector(preferredTab: appModel.selectedInspectorTab)
            } label: {
                Label(appModel.isInspectorVisible ? "Hide Tools" : "Show Tools", systemImage: "sidebar.right")
            }
            .buttonStyle(.plain)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Color.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(ReaderTheme.teal, in: Capsule())
            .keyboardShortcut("i", modifiers: [.command, .option])
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(ReaderTheme.toolbarGradient, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(ReaderTheme.lineSoft, lineWidth: 1)
        )
        .shadow(color: ReaderTheme.shadow, radius: 18, y: 8)
    }
}
