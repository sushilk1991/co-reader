import CoreaderKit
import SwiftUI

/// First run: what the app is, where the library lives, what to connect. Two short steps.
struct OnboardingView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var palette
    @State private var step = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if step == 0 {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Coreader")
                        .font(.system(size: 17, weight: .semibold, design: .serif)).italic()
                        .foregroundStyle(palette.accent)
                    Text("A quiet place to read,\nand a memory for what you read.")
                        .font(Typo.display(30, weight: .regular))
                        .foregroundStyle(palette.ink)
                        .lineSpacing(3)
                        .padding(.top, 14)
                    VStack(alignment: .leading, spacing: 14) {
                        point("book", "EPUB, PDF, MOBI and web articles on one shelf.")
                        point("highlighter", "Highlights, notes and snipped figures saved as plain Markdown you own.")
                        point("sparkles", "Ask about a passage or the whole book, using the AI agents already on your Mac.")
                        point("rectangle.stack", "A few highlights come back each day so they stick.")
                    }
                    .padding(.top, 26)
                }
                .transition(.opacity)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Set up").font(Typo.display(26, weight: .regular)).foregroundStyle(palette.ink)
                    Text("Everything here is optional and can be changed later in Settings.")
                        .font(Typo.ui(12.5)).foregroundStyle(palette.secondary).padding(.bottom, 8)
                    LibraryLocationRow()
                    ConnectionsList(connectsMastiskAutomatically: true)
                }
                .transition(.opacity)
            }

            Spacer(minLength: 20)

            HStack {
                HStack(spacing: 6) {
                    ForEach(0..<2, id: \.self) { i in
                        Circle().fill(i == step ? palette.ink : palette.rule).frame(width: 6, height: 6)
                    }
                }
                Spacer()
                if step == 1 { Button("Back") { withAnimation { step = 0 } }.buttonStyle(.plain).foregroundStyle(palette.secondary).padding(.trailing, 10) }
                Button {
                    if step == 0 { withAnimation { step = 1 } } else { app.hasOnboarded = true }
                } label: {
                    Text(step == 0 ? "Continue" : "Start reading")
                        .font(Typo.ui(13, weight: .semibold))
                        .foregroundStyle(palette.page)
                        .padding(.horizontal, 22).frame(height: 36)
                        .background(palette.accent, in: Capsule())
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(36)
        .frame(width: 620, height: 560)
        .background(palette.page)
    }

    private func point(_ symbol: String, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Image(systemName: symbol).font(.system(size: 14)).foregroundStyle(palette.accent).frame(width: 22)
            Text(text).font(Typo.ui(14)).foregroundStyle(palette.ink).lineSpacing(2)
        }
    }
}
