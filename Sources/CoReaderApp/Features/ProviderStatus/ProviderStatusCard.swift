import SwiftUI

struct ProviderStatusCard: View {
    let provider: AIProviderStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(provider.kind.displayName)
                    .font(.headline)

                Spacer()

                Label(
                    provider.isAvailable ? "Available" : "Unavailable",
                    systemImage: provider.isAvailable ? "checkmark.circle.fill" : "xmark.circle.fill"
                )
                .labelStyle(.titleAndIcon)
                .foregroundStyle(provider.isAvailable ? .green : .red)
            }

            Text(provider.detail)
                .foregroundStyle(.secondary)

            if !provider.models.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(provider.models, id: \.self) { model in
                            Text(model)
                                .font(.caption.weight(.medium))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(.tertiary.opacity(0.5), in: Capsule())
                        }
                    }
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.22), in: RoundedRectangle(cornerRadius: 16))
    }
}
