import SwiftUI

struct ImportedDocumentRow: View {
    let document: ReaderDocument
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: document.kind == .pdf ? "doc.richtext" : "books.vertical")
                    .font(.title3)
                    .foregroundStyle(isSelected ? ReaderTheme.teal : ReaderTheme.slate)

                VStack(alignment: .leading, spacing: 4) {
                    Text(document.title)
                        .font(.headline)
                        .foregroundStyle(ReaderTheme.ink)
                        .multilineTextAlignment(.leading)

                    Text(document.kind.displayName)
                        .font(.caption)
                        .foregroundStyle(ReaderTheme.slate)
                }

                Spacer()
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(backgroundStyle, in: RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(isSelected ? ReaderTheme.teal.opacity(0.28) : ReaderTheme.lineSoft, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var backgroundStyle: some ShapeStyle {
        if isSelected {
            return AnyShapeStyle(ReaderTheme.tealSoft)
        }

        return AnyShapeStyle(ReaderTheme.paper.opacity(0.88))
    }
}
