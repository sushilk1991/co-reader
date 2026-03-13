import AppKit
import Observation
import SwiftUI

struct ReaderVisualsPanel: View {
    @Bindable var appModel: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Visuals")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(ReaderTheme.ink)

                Text("Figures and page visuals extracted from the current PDF.")
                    .font(.subheadline)
                    .foregroundStyle(ReaderTheme.slate)
            }

            if appModel.documentVisuals.isEmpty {
                ContentUnavailableView(
                    "No visuals found",
                    systemImage: "photo.on.rectangle",
                    description: Text("This PDF does not expose extractable image-backed visuals yet.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(appModel.documentVisuals) { visual in
                            Button {
                                appModel.selectVisual(visual)
                            } label: {
                                HStack(spacing: 12) {
                                    if let image = NSImage(data: visual.imageData) {
                                        Image(nsImage: image)
                                            .resizable()
                                            .aspectRatio(contentMode: .fit)
                                            .frame(width: 96, height: 72)
                                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                    }

                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Page \(visual.pageIndex + 1)")
                                            .font(.headline)
                                            .foregroundStyle(ReaderTheme.ink)

                                        Text(visual.kind == .embeddedImage ? "Embedded image" : "Page snapshot")
                                            .font(.caption)
                                            .foregroundStyle(ReaderTheme.slate)
                                    }

                                    Spacer()
                                }
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(
                                    Color.white.opacity(appModel.selectedVisual?.id == visual.id ? 0.96 : 0.82),
                                    in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }
}
