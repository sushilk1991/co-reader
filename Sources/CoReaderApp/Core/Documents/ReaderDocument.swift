import Foundation

struct ReaderDocument: Equatable, Identifiable, Sendable {
    let id: UUID
    let title: String
    let fileURL: URL
    let kind: DocumentKind

    init(fileURL: URL) {
        self.id = UUID()
        self.fileURL = fileURL.standardizedFileURL
        self.title = fileURL.deletingPathExtension().lastPathComponent
        self.kind = DocumentKind(fileURL: fileURL)
    }
}

private extension DocumentKind {
    init(fileURL: URL) {
        switch fileURL.pathExtension.lowercased() {
        case "pdf":
            self = .pdf
        case "epub":
            self = .epub
        default:
            self = .unknown
        }
    }
}
