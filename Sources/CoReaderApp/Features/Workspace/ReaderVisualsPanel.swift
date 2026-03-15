import AppKit
import Observation
import SwiftUI

struct ReaderVisualsPanel: View {
    @Bindable var appModel: AppModel
    @State private var actionStatus: VisualActionStatus?
    @State private var expandedVisualIDs: Set<UUID> = []
    @State private var lightboxVisual: DocumentVisualAsset?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header

                if let selectedVisual {
                    selectedVisualSection(for: selectedVisual)
                } else {
                    emptyState
                }

                if !appModel.documentVisuals.isEmpty {
                    extractedVisualsSection
                }
            }
            .padding(.bottom, 10)
        }
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .overlay {
            if let visual = lightboxVisual {
                ZStack {
                    Color.black.opacity(0.85)
                        .ignoresSafeArea()
                        .onTapGesture {
                            lightboxVisual = nil
                        }

                    VStack(spacing: 16) {
                        HStack {
                            Text("Page \(visual.pageIndex + 1)")
                                .font(.headline)
                                .foregroundStyle(.white)
                            Spacer()
                            Button {
                                lightboxVisual = nil
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.title2)
                                    .foregroundStyle(.white.opacity(0.8))
                            }
                            .buttonStyle(.borderless)
                        }
                        .padding(.horizontal, 24)

                        if let image = NSImage(data: visual.imageData) {
                            Image(nsImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .padding(24)
                        }
                    }
                }
                .onExitCommand {
                    lightboxVisual = nil
                }
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: lightboxVisual?.id)
        .onAppear {
            expandSelectedVisualIfNeeded()
        }
        .onChange(of: appModel.selectedVisual?.id) { _, _ in
            actionStatus = nil
            expandSelectedVisualIfNeeded()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Visuals")
                .font(.title3.weight(.semibold))
                .foregroundStyle(ReaderTheme.ink)

            Text("Extracted figures and fallback page snapshots stay in one vertical browser, so you can inspect, explain, and export without sideways hunting.")
                .font(.subheadline)
                .foregroundStyle(ReaderTheme.smoke)
        }
    }

    private var selectedVisual: DocumentVisualAsset? {
        appModel.selectedVisual ?? appModel.documentVisuals.first
    }

    private var hasVisionModel: Bool {
        visionModelName != nil
    }

    private var visionModelName: String? {
        appModel.providerStatuses
            .compactMap(\.preferredVisionModel)
            .first
    }

    private var canExplainVisuals: Bool {
        hasVisionModel && (selectedVisual != nil || appModel.currentPageIndex != nil)
    }

    private func selectedVisualSection(for visual: DocumentVisualAsset) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("Selected Visual")
                    .font(.headline)
                    .foregroundStyle(ReaderTheme.ink)

                Spacer()

                metadataPill(kindLabel(for: visual), tint: ReaderTheme.brass, background: ReaderTheme.brassSoft)
            }

            visualPreviewCard(for: visual, height: 224)

            HStack(alignment: .top, spacing: 10) {
                Label("Page \(visual.pageIndex + 1)", systemImage: "doc.text.image")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(ReaderTheme.ink)

                Text("\(visual.pixelWidth) × \(visual.pixelHeight) px")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(ReaderTheme.smoke)

                Spacer()
            }

            Text(visual.suggestedFilename)
                .font(.caption)
                .foregroundStyle(ReaderTheme.smoke)
                .textSelection(.enabled)
                .lineLimit(2)

            visionStatusCard
            actionButtons(for: visual)

            if let actionStatus {
                Label(actionStatus.message, systemImage: actionStatus.systemImage)
                    .font(.caption)
                    .foregroundStyle(actionStatus.tint)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(actionStatus.background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
        .padding(18)
        .background(ReaderTheme.paperGradient, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(ReaderTheme.lineSoft, lineWidth: 1)
        )
    }

    private var extractedVisualsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Extracted Visuals")
                    .font(.headline)
                    .foregroundStyle(ReaderTheme.ink)

                Spacer()

                Text("\(appModel.documentVisuals.count) item\(appModel.documentVisuals.count == 1 ? "" : "s")")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(ReaderTheme.smoke)
            }

            LazyVStack(spacing: 10) {
                ForEach(appModel.documentVisuals) { visual in
                    DisclosureGroup(isExpanded: expansionBinding(for: visual.id)) {
                        VStack(alignment: .leading, spacing: 12) {
                            visualPreviewCard(for: visual, height: 172)

                            HStack(spacing: 8) {
                                metadataPill("Page \(visual.pageIndex + 1)", tint: ReaderTheme.ink, background: ReaderTheme.canvas)
                                metadataPill(kindLabel(for: visual), tint: ReaderTheme.brass, background: ReaderTheme.brassSoft)
                                Spacer()
                                Text("\(visual.pixelWidth) × \(visual.pixelHeight)")
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(ReaderTheme.smoke)
                            }

                            HStack(spacing: 8) {
                                Button("Use This", systemImage: "checkmark.circle") {
                                    appModel.selectVisual(visual)
                                }
                                .buttonStyle(.bordered)
                                .tint(ReaderTheme.teal)

                                Button("Explain", systemImage: "sparkles") {
                                    selectAndExplain(visual)
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(ReaderTheme.teal)
                                .disabled(!hasVisionModel)

                                Button("Save", systemImage: "square.and.arrow.down") {
                                    exportVisual(visual, revealInFinder: false)
                                }
                                .buttonStyle(.bordered)
                                .tint(ReaderTheme.brass)
                            }
                        }
                        .padding(.top, 12)
                    } label: {
                        visualRowHeader(for: visual)
                    }
                    .padding(14)
                    .background(
                        appModel.selectedVisual?.id == visual.id ? ReaderTheme.tealSoft : ReaderTheme.paper.opacity(0.94),
                        in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(
                                appModel.selectedVisual?.id == visual.id ? ReaderTheme.teal.opacity(0.45) : ReaderTheme.lineSoft,
                                lineWidth: 1
                            )
                    )
                }
            }
        }
        .padding(18)
        .background(ReaderTheme.panelGradient, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(ReaderTheme.lineSoft, lineWidth: 1)
        )
    }

    private var visionStatusCard: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: hasVisionModel ? "eye.circle.fill" : "bolt.slash")
                .font(.title3)
                .foregroundStyle(hasVisionModel ? ReaderTheme.teal : ReaderTheme.rose)

            VStack(alignment: .leading, spacing: 4) {
                Text(hasVisionModel ? "Diagram explanation is ready." : "Vision model required.")
                    .font(.headline)
                    .foregroundStyle(ReaderTheme.ink)

                Text(
                    hasVisionModel
                        ? "Ollama will use \(visionModelName ?? "a local vision model") for image-grounded explanations."
                        : "Install a local Ollama vision model such as Llava, Gemma 3, or Qwen2-VL to explain diagrams."
                )
                .font(.subheadline)
                .foregroundStyle(ReaderTheme.smoke)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            hasVisionModel ? ReaderTheme.tealSoft : ReaderTheme.roseSoft,
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 14) {
            ContentUnavailableView(
                "No extracted visuals yet",
                systemImage: "photo.on.rectangle.angled",
                description: Text("When a PDF exposes embedded images, they will appear here as separate figure crops instead of full-page screenshots.")
            )
            .frame(maxWidth: .infinity, minHeight: 260, alignment: .center)

            if appModel.currentPageIndex != nil {
                Button("Explain Current Page Snapshot", systemImage: "eye") {
                    Task {
                        await appModel.runQuickAction(.explainVisuals)
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(ReaderTheme.teal)
                .disabled(!canExplainVisuals)
            }
        }
        .padding(18)
        .background(ReaderTheme.paperGradient, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(ReaderTheme.lineSoft, lineWidth: 1)
        )
    }

    private func visualPreviewCard(for visual: DocumentVisualAsset, height: CGFloat) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(ReaderTheme.paper)

            if let image = NSImage(data: visual.imageData) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(16)
            } else {
                ContentUnavailableView(
                    "Preview unavailable",
                    systemImage: "exclamationmark.triangle",
                    description: Text("Co-Reader extracted the visual asset, but the preview could not be decoded.")
                )
                .padding(18)
            }
        }
        .onTapGesture { lightboxVisual = visual }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(ReaderTheme.lineSoft, lineWidth: 1)
        )
    }

    private func visualRowHeader(for visual: DocumentVisualAsset) -> some View {
        HStack(alignment: .center, spacing: 12) {
            thumbnail(for: visual)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text("Page \(visual.pageIndex + 1)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(ReaderTheme.ink)

                    if appModel.selectedVisual?.id == visual.id {
                        metadataPill("Current", tint: ReaderTheme.teal, background: ReaderTheme.tealSoft)
                    }
                }

                Text(kindLabel(for: visual))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(ReaderTheme.smoke)

                Text(visual.suggestedFilename)
                    .font(.caption2)
                    .foregroundStyle(ReaderTheme.smoke)
                    .lineLimit(1)
            }

            Spacer()
        }
        .contentShape(Rectangle())
        .onTapGesture {
            appModel.selectVisual(visual)
            _ = withAnimation(.easeInOut(duration: 0.18)) {
                expandedVisualIDs.insert(visual.id)
            }
        }
    }

    private func thumbnail(for visual: DocumentVisualAsset) -> some View {
        Group {
            if let image = NSImage(data: visual.imageData) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Rectangle()
                    .fill(ReaderTheme.panel)
                    .overlay(
                        Image(systemName: "photo")
                            .foregroundStyle(ReaderTheme.smoke)
                    )
            }
        }
        .frame(width: 74, height: 74)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(ReaderTheme.lineSoft, lineWidth: 1)
        )
    }

    private func actionButtons(for visual: DocumentVisualAsset) -> some View {
        HStack(spacing: 10) {
            Button("Explain Diagram", systemImage: "sparkles") {
                selectAndExplain(visual)
            }
            .buttonStyle(.borderedProminent)
            .tint(ReaderTheme.teal)
            .disabled(!canExplainVisuals)

            Button("Save PNG", systemImage: "square.and.arrow.down") {
                exportVisual(visual, revealInFinder: false)
            }
            .buttonStyle(.bordered)
            .tint(ReaderTheme.brass)

            Button("Reveal", systemImage: "folder") {
                exportVisual(visual, revealInFinder: true)
            }
            .buttonStyle(.bordered)
        }
    }

    private func metadataPill(_ title: String, tint: Color, background: Color) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(background, in: Capsule())
    }

    private func expansionBinding(for visualID: UUID) -> Binding<Bool> {
        Binding(
            get: { expandedVisualIDs.contains(visualID) },
            set: { isExpanded in
                if isExpanded {
                    expandedVisualIDs.insert(visualID)
                } else {
                    expandedVisualIDs.remove(visualID)
                }
            }
        )
    }

    private func expandSelectedVisualIfNeeded() {
        if let selectedVisual {
            expandedVisualIDs.insert(selectedVisual.id)
        }
    }

    private func selectAndExplain(_ visual: DocumentVisualAsset) {
        appModel.selectVisual(visual)
        Task {
            await appModel.runQuickAction(.explainVisuals)
        }
    }

    private func exportVisual(_ visual: DocumentVisualAsset, revealInFinder: Bool) {
        appModel.selectVisual(visual)
        exportSelectedVisual(revealInFinder: revealInFinder)
    }

    private func exportSelectedVisual(revealInFinder: Bool) {
        do {
            let exportedURL = try appModel.exportSelectedVisual()
            if revealInFinder {
                NSWorkspace.shared.activateFileViewerSelecting([exportedURL])
                actionStatus = .success("Saved PNG and revealed it in Finder.")
            } else {
                actionStatus = .success("Saved \(exportedURL.lastPathComponent) to your local exports folder.")
            }
        } catch {
            actionStatus = .failure(error.localizedDescription)
        }
    }

    private func kindLabel(for visual: DocumentVisualAsset) -> String {
        switch visual.kind {
        case .embeddedImage:
            "Embedded image"
        case .pageSnapshot:
            "Page snapshot"
        }
    }
}

private struct VisualActionStatus {
    let message: String
    let systemImage: String
    let tint: Color
    let background: Color

    static func success(_ message: String) -> Self {
        Self(
            message: message,
            systemImage: "checkmark.circle.fill",
            tint: ReaderTheme.teal,
            background: ReaderTheme.teal.opacity(0.10)
        )
    }

    static func failure(_ message: String) -> Self {
        Self(
            message: message,
            systemImage: "exclamationmark.triangle.fill",
            tint: ReaderTheme.rose,
            background: ReaderTheme.rose.opacity(0.10)
        )
    }
}
