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
                                .background(ReaderTheme.paper.opacity(0.94), in: Capsule())
                                .overlay(
                                    Capsule()
                                        .stroke(ReaderTheme.lineSoft, lineWidth: 1)
                                )
                        }
                    }
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ReaderTheme.paper.opacity(0.94), in: RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(ReaderTheme.lineSoft, lineWidth: 1)
        )
    }
}
