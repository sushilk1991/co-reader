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

            Spacer()
        }
        .padding(32)
    }
}

#Preview {
    ProviderStatusView(appModel: AppModel())
        .frame(width: 980, height: 640)
}
