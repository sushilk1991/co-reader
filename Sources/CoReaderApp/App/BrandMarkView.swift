import SwiftUI

struct BrandMarkView: View {
    let size: CGFloat

    init(size: CGFloat = 44) {
        self.size = size
    }

    var body: some View {
        Image("CoReaderMark")
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: max(14, size * 0.24), style: .continuous))
            .shadow(color: ReaderTheme.ink.opacity(0.16), radius: size * 0.18, y: size * 0.08)
            .accessibilityHidden(true)
    }
}
