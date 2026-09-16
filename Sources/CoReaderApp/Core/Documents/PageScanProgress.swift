/// Progress of a page-by-page pass over a document (visual extraction, text
/// extraction). `completedPages` counts pages fully processed so far.
struct PageScanProgress: Equatable, Sendable {
    let completedPages: Int
    let totalPages: Int

    var fraction: Double {
        guard totalPages > 0 else {
            return 0
        }

        return Double(completedPages) / Double(totalPages)
    }

    var label: String {
        "\(completedPages) of \(totalPages) pages"
    }
}
