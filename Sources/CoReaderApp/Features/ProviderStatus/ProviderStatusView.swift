import SwiftUI

struct ProviderStatusView: View {
    let appModel: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(appModel.appTitle)
                .font(.largeTitle.weight(.semibold))

            Text("AI-Powered PDF and EPUB Co-Reader")
                .font(.title3)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                Text(appModel.statusHeadline)
                    .font(.headline)

                Text(appModel.statusDetail)
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 18))

            if appModel.providerStatuses.isEmpty {
                ContentUnavailableView(
                    "Provider status pending",
                    systemImage: "network.badge.shield.half.filled",
                    description: Text("The app will populate Ollama and Claude availability after the initial probe completes.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(appModel.providerStatuses) { provider in
                        ProviderStatusCard(provider: provider)
                    }
                }
            }

            Spacer()
        }
        .padding(32)
        .task {
            await appModel.refreshProvidersIfNeeded()
        }
    }
}

#Preview {
    ProviderStatusView(appModel: AppModel())
        .frame(width: 980, height: 640)
}
