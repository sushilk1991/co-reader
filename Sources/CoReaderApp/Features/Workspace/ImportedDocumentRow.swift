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
        }
        .buttonStyle(.plain)
    }

    private var backgroundStyle: some ShapeStyle {
        if isSelected {
            return AnyShapeStyle(ReaderTheme.teal.opacity(0.12))
        }

        return AnyShapeStyle(Color.white.opacity(0.7))
    }
}
