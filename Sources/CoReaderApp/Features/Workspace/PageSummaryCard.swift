import SwiftUI

/// What the card over the page says. A failure is an event that happened to one
/// page and can be dismissed; `unavailable` states current app state (no provider),
/// so there is nothing to dismiss and it stays as long as it is true.
enum PageSummaryCardContent: Equatable {
    case summary(String)
    case failure(String)
    case unavailable(String)

    var title: String {
        switch self {
        case .summary:
            "Auto-Summary"
        case .failure:
            "Auto-Summary Failed"
        case .unavailable:
            "Auto-Summary Unavailable"
        }
    }

    var isDismissable: Bool {
        switch self {
        case .summary, .failure:
            true
        case .unavailable:
            false
        }
    }
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
                Text(content.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(ReaderTheme.smoke)

                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(ReaderTheme.ink)
                    .lineLimit(6)
            }

            Spacer()

            if content.isDismissable {
                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(ReaderTheme.smoke)
                }
                .buttonStyle(.borderless)
            }
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

    private var message: String {
        switch content {
        case let .summary(text), let .failure(text), let .unavailable(text):
            text
        }
    }

    private var iconName: String {
        switch content {
        case .summary:
            "sparkles"
        case .failure:
            "exclamationmark.triangle"
        case .unavailable:
            "bolt.slash"
        }
    }

    private var tint: Color {
        switch content {
        case .summary:
            ReaderTheme.teal
        case .failure:
            ReaderTheme.rose
        case .unavailable:
            ReaderTheme.smoke
        }
    }

    private var softTint: Color {
        switch content {
        case .summary:
            ReaderTheme.tealSoft
        case .failure:
            ReaderTheme.roseSoft
        case .unavailable:
            ReaderTheme.lineSoft
        }
    }
}
