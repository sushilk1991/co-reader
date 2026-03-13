import SwiftUI

struct ChatMessageBubble: View {
    let message: ChatMessage

    var body: some View {
        VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 6) {
            Text(message.role == .user ? "You" : "Co-Reader")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(message.content)
                .font(.body)
                .textSelection(.enabled)
                .padding(14)
                .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)
                .background(backgroundStyle, in: RoundedRectangle(cornerRadius: 16))
        }
        .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)
    }

    private var backgroundStyle: AnyShapeStyle {
        if message.role == .user {
            return AnyShapeStyle(Color.accentColor.opacity(0.16))
        }

        return AnyShapeStyle(.quaternary.opacity(0.3))
    }
}
