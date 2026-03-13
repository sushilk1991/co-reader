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
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)

                VStack(alignment: .leading, spacing: 4) {
                    Text(document.title)
                        .font(.headline)
                        .multilineTextAlignment(.leading)

                    Text(document.kind.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
            return AnyShapeStyle(.tint.opacity(0.15))
        }

        return AnyShapeStyle(.quaternary.opacity(0.18))
    }
}
