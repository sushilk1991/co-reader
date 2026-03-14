import SwiftUI

struct ReadingProgressBar: View {
    let progress: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(ReaderTheme.lineSoft.opacity(0.5))
                    .frame(height: 3)

                Capsule()
                    .fill(ReaderTheme.teal)
                    .frame(width: max(3, proxy.size.width * progress), height: 3)
                    .animation(.spring(response: 0.4, dampingFraction: 0.9), value: progress)
            }
        }
        .frame(height: 3)
    }
}
