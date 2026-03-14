import SwiftUI

struct ChatMessageBubble: View {
    let message: ChatMessage

    var body: some View {
        VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 6) {
            Text(message.role == .user ? "You" : "Co-Reader")
                .font(.caption.weight(.semibold))
                .foregroundStyle(message.role == .user ? ReaderTheme.teal : ReaderTheme.smoke)

            Text(message.content)
                .font(.body)
                .foregroundStyle(ReaderTheme.ink)
                .textSelection(.enabled)
                .padding(14)
                .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)
                .background(backgroundStyle, in: RoundedRectangle(cornerRadius: 16))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(borderColor, lineWidth: 1)
                )
        }
        .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)
    }

    private var backgroundStyle: AnyShapeStyle {
        if message.role == .user {
            return AnyShapeStyle(ReaderTheme.tealSoft)
        }

        return AnyShapeStyle(ReaderTheme.panelRaised.opacity(0.95))
    }

    private var borderColor: Color {
        message.role == .user ? ReaderTheme.teal.opacity(0.28) : ReaderTheme.lineSoft
    }
}
