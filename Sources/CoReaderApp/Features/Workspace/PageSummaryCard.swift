import SwiftUI

enum PageSummaryCardContent: Equatable {
    case summary(String)
    case failure(String)
}

struct PageSummaryCard: View {
    let content: PageSummaryCardContent
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: iconName)
                .font(.subheadline)
                .foregroundStyle(tint)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(ReaderTheme.smoke)

                Text(message)
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
                .stroke(softTint, lineWidth: 1)
        )
        .shadow(color: ReaderTheme.shadow, radius: 12, y: 6)
    }

    private var title: String {
        switch content {
        case .summary:
            "Auto-Summary"
        case .failure:
            "Auto-Summary Failed"
        }
    }

    private var message: String {
        switch content {
        case let .summary(text), let .failure(text):
            text
        }
    }

    private var iconName: String {
        switch content {
        case .summary:
            "sparkles"
        case .failure:
            "exclamationmark.triangle"
        }
    }

    private var tint: Color {
        switch content {
        case .summary:
            ReaderTheme.teal
        case .failure:
            ReaderTheme.rose
        }
    }

    private var softTint: Color {
        switch content {
        case .summary:
            ReaderTheme.tealSoft
        case .failure:
            ReaderTheme.roseSoft
        }
    }
}
