import SwiftUI

/// One-line, dismissible notice about the last session (missing files, unreadable state).
struct SessionNoticeBanner: View {
    let message: String
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(ReaderTheme.rose)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(ReaderTheme.ink)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()

            Button("Dismiss", action: onDismiss)
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(ReaderTheme.roseSoft, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(ReaderTheme.lineSoft, lineWidth: 1)
        )
    }
}
