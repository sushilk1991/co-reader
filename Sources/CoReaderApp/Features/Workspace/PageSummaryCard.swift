import SwiftUI

struct PageSummaryCard: View {
    let summary: String
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "sparkles")
                .font(.subheadline)
                .foregroundStyle(ReaderTheme.teal)

            VStack(alignment: .leading, spacing: 4) {
                Text("Auto-Summary")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(ReaderTheme.smoke)

                Text(summary)
                    .font(.subheadline)
                    .foregroundStyle(ReaderTheme.ink)
                    .lineLimit(6)
            }

            Spacer()

            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(ReaderTheme.smoke)
            }
            .buttonStyle(.borderless)
        }
        .padding(14)
        .frame(maxWidth: 420, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(ReaderTheme.tealSoft, lineWidth: 1)
        )
        .shadow(color: ReaderTheme.shadow, radius: 12, y: 6)
    }
}
