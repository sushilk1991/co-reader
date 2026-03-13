import SwiftUI

struct ProviderStatusCard: View {
    let provider: AIProviderStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(provider.kind.displayName)
                    .font(.headline)
                    .foregroundStyle(ReaderTheme.ink)

                Spacer()

                Label(
                    provider.isAvailable ? "Available" : "Unavailable",
                    systemImage: provider.isAvailable ? "checkmark.circle.fill" : "xmark.circle.fill"
                )
                .labelStyle(.titleAndIcon)
                .foregroundStyle(provider.isAvailable ? ReaderTheme.teal : ReaderTheme.rose)
            }

            Text(provider.detail)
                .foregroundStyle(ReaderTheme.slate)

            if !provider.models.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(provider.models, id: \.self) { model in
                            Text(model)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(ReaderTheme.ink)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(ReaderTheme.canvas.opacity(0.85), in: Capsule())
                        }
                    }
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.78), in: RoundedRectangle(cornerRadius: 18))
    }
}
