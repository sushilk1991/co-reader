import CoreaderKit
import SwiftUI

/// A few past highlights a day, so what was read stays read.
struct ReviewView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    @State private var total = 0
    @State private var revealed = false

    var body: some View {
        let review = app.review
        VStack(spacing: 0) {
            HStack {
                Text("Daily review").labelStyle(palette)
                Spacer()
                if total > 0 {
                    Text("\(total - review.due.count) of \(total)").font(Typo.ui(11.5).monospacedDigit()).foregroundStyle(palette.tertiary)
                }
                Button { dismiss() } label: {
                    Image(systemName: "xmark").font(.system(size: 11, weight: .semibold)).foregroundStyle(palette.tertiary)
                        .frame(width: 26, height: 26).background(palette.ink.opacity(0.06), in: Circle())
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
                .accessibilityLabel("Close")
                .padding(.leading, 10)
            }
            .padding(.horizontal, 28)
            .padding(.top, 22)

            if let card = review.due.first {
                VStack(alignment: .leading, spacing: 0) {
                    Spacer(minLength: 16)
                    Text("“\(card.annotation.quote)”")
                        .font(Typo.serif(card.annotation.quote.count > 360 ? 17 : 21))
                        .lineSpacing(6)
                        .foregroundStyle(palette.ink)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    HStack(spacing: 10) {
                        BookCover(entry: card.entry, width: 26)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(card.entry.book.title).font(Typo.display(13)).foregroundStyle(palette.ink).lineLimit(1)
                            Text([card.entry.book.authorLine, card.annotation.locator.label ?? ""].filter { !$0.isEmpty }.joined(separator: " · "))
                                .font(Typo.ui(11)).foregroundStyle(palette.tertiary).lineLimit(1)
                        }
                        Spacer()
                        Button("Open in book") {
                            dismiss()
                            app.open(card.entry.id, at: .annotation(bookID: card.entry.id, annotationID: card.id))
                        }
                        .buttonStyle(.plain).font(Typo.ui(11.5, weight: .medium)).foregroundStyle(palette.accent)
                    }
                    .padding(.top, 22)

                    if !card.annotation.note.isEmpty {
                        if revealed {
                            MarkdownText(text: card.annotation.note, baseSize: 13)
                                .padding(12)
                                .background(palette.surface, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                                .padding(.top, 16)
                        } else {
                            Button("Show my note") { withAnimation { revealed = true } }
                                .buttonStyle(.plain).font(Typo.ui(12, weight: .medium)).foregroundStyle(palette.secondary).padding(.top, 16)
                        }
                    }
                    Spacer(minLength: 16)
                }
                .padding(.horizontal, 44)
                .id(card.id)
                .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .move(edge: .leading).combined(with: .opacity)))

                HStack(spacing: 10) {
                    grade("Forgot", "1", .forgot, card)
                    grade("Hazy", "2", .hard, card)
                    grade("Remembered", "3", .good, card)
                    grade("Know it cold", "4", .easy, card)
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 26)
            } else {
                VStack(spacing: 10) {
                    Spacer()
                    Image(systemName: "checkmark.circle").font(.system(size: 30, weight: .light)).foregroundStyle(palette.accent)
                    Text(total > 0 ? "Done for today" : "Nothing to review yet").font(Typo.display(22, weight: .regular)).foregroundStyle(palette.ink)
                    Text(total > 0 ? "These highlights come back when you are about to forget them." : "Highlights you make show up here from tomorrow, a few each day.")
                        .font(Typo.ui(13)).foregroundStyle(palette.secondary).multilineTextAlignment(.center).frame(maxWidth: 340)
                    Spacer()
                    Spacer()
                }
            }
        }
        .frame(width: 660, height: 500)
        .background(palette.page)
        .onAppear { total = review.due.count }
    }

    private func grade(_ title: String, _ key: String, _ grade: ReviewGrade, _ card: ReviewModel.Card) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.25)) {
                revealed = false
                app.review.grade(card, grade)
            }
        } label: {
            VStack(spacing: 2) {
                Text(title).font(Typo.ui(12.5, weight: .medium)).foregroundStyle(palette.ink)
                Text(key).font(Typo.ui(10).monospacedDigit()).foregroundStyle(palette.tertiary)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 46)
            .background(palette.raised, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(palette.rule, lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .keyboardShortcut(KeyEquivalent(Character(key)), modifiers: [])
    }
}
