import AppKit
import Observation
import SwiftUI

struct ReaderVisualsPanel: View {
    @Bindable var appModel: AppModel
    @State private var actionStatus: VisualActionStatus?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Visuals")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(ReaderTheme.ink)

                Text("Extracted figures, snapshots, and diagram actions for the current reading context.")
                    .font(.subheadline)
                    .foregroundStyle(ReaderTheme.slate)
            }

            if let selectedVisual {
                ScrollView {
                    selectedVisualContent(for: selectedVisual)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.bottom, 8)
                }
            } else {
                emptyState
            }
        }
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .onChange(of: appModel.selectedVisual?.id) { _, _ in
            actionStatus = nil
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

    @ViewBuilder
    private func selectedVisualContent(for visual: DocumentVisualAsset) -> some View {
        visualPreviewCard(for: visual)

        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Label("Page \(visual.pageIndex + 1)", systemImage: "doc.text.image")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(ReaderTheme.ink)

                Text(kindLabel(for: visual))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(ReaderTheme.brass)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(ReaderTheme.canvas.opacity(0.92), in: Capsule())

                Spacer()
            }

            Text("\(visual.pixelWidth) × \(visual.pixelHeight) px")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(ReaderTheme.ink)

            Text(visual.suggestedFilename)
                .font(.caption)
                .foregroundStyle(ReaderTheme.slate)
                .textSelection(.enabled)
                .lineLimit(2)
        }

        visionStatusCard

        HStack(spacing: 10) {
            Button("Explain Diagram", systemImage: "sparkles") {
                Task {
                    await appModel.runQuickAction(.explainVisuals)
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(ReaderTheme.teal)
            .disabled(!canExplainVisuals)

            Button("Save PNG", systemImage: "square.and.arrow.down") {
                exportSelectedVisual(revealInFinder: false)
            }
            .buttonStyle(.bordered)
            .tint(ReaderTheme.brass)

            Button("Reveal", systemImage: "folder") {
                exportSelectedVisual(revealInFinder: true)
            }
            .buttonStyle(.bordered)
        }

        if let actionStatus {
            Label(actionStatus.message, systemImage: actionStatus.systemImage)
                .font(.caption)
                .foregroundStyle(actionStatus.tint)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(actionStatus.background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }

        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Extracted from this document")
                    .font(.headline)
                    .foregroundStyle(ReaderTheme.ink)

                Spacer()

                Text("\(appModel.documentVisuals.count) visual\(appModel.documentVisuals.count == 1 ? "" : "s")")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(ReaderTheme.slate)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(appModel.documentVisuals) { candidate in
                        visualThumbnail(candidate)
                    }
                }
                .padding(.vertical, 2)
            }
        }
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
                .foregroundStyle(ReaderTheme.slate)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            hasVisionModel ? ReaderTheme.teal.opacity(0.10) : ReaderTheme.rose.opacity(0.10),
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 14) {
            ContentUnavailableView(
                "No extracted visuals yet",
                systemImage: "photo.on.rectangle.angled",
                description: Text("This PDF has no image-backed assets exposed yet. You can still explain the current page once a vision-capable Ollama model is available.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)

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
    }

    private func visualPreviewCard(for visual: DocumentVisualAsset) -> some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.98),
                            ReaderTheme.canvas.opacity(0.92)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            if let image = NSImage(data: visual.imageData) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(18)
            } else {
                ContentUnavailableView(
                    "Preview unavailable",
                    systemImage: "exclamationmark.triangle",
                    description: Text("Co-Reader extracted the visual asset, but the preview could not be decoded.")
                )
                .padding(18)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 248)
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(ReaderTheme.chromeStrong.opacity(0.85), lineWidth: 1)
        )
        .shadow(color: ReaderTheme.ink.opacity(0.05), radius: 16, y: 8)
    }

    private func visualThumbnail(_ visual: DocumentVisualAsset) -> some View {
        Button {
            appModel.selectVisual(visual)
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                if let image = NSImage(data: visual.imageData) {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 120, height: 84)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                } else {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(ReaderTheme.chromeStrong.opacity(0.8))
                        .frame(width: 120, height: 84)
                        .overlay(
                            Image(systemName: "photo")
                                .foregroundStyle(ReaderTheme.slate)
                        )
                }

                Text("Page \(visual.pageIndex + 1)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(ReaderTheme.ink)
            }
            .padding(10)
            .background(
                appModel.selectedVisual?.id == visual.id ? Color.white.opacity(0.96) : Color.white.opacity(0.78),
                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(
                        appModel.selectedVisual?.id == visual.id ? ReaderTheme.teal.opacity(0.7) : ReaderTheme.chromeStrong.opacity(0.6),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
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
