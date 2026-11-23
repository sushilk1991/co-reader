import CoreaderKit
import SwiftUI

enum ShelfTab: String, CaseIterable, Identifiable {
    case library, reading, toRead, read
    var id: String { rawValue }
    var title: String {
        switch self {
        case .library: "Library"
        case .reading: "Reading"
        case .toRead: "To Read"
        case .read: "Read"
        }
    }
    var status: ReadingStatus? {
        switch self {
        case .library: nil
        case .reading: .reading
        case .toRead: .toRead
        case .read: .read
        }
    }
}

enum ShelfSort: String, CaseIterable, Identifiable {
    case recent, title, author, rating, progress, added
    var id: String { rawValue }
    var title: String {
        switch self {
        case .recent: "Recently opened"
        case .added: "Recently added"
        case .title: "Title"
        case .author: "Author"
        case .rating: "Rating"
        case .progress: "Progress"
        }
    }
}

/// Filters for the shelf. Kept apart from the view so they survive tab switches.
@MainActor
@Observable
final class ShelfModel {
    var tab: ShelfTab = .library
    var kind: BookKind?
    /// Exact star filter: nil shows everything.
    var stars: Int?
    var sort: ShelfSort = .recent
    var query = ""
    var detail: BookEntry?

    func visible(_ books: [BookEntry]) -> [BookEntry] {
        let q = query.trimmingCharacters(in: .whitespaces).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        let filtered = books.filter { e in
            let b = e.book
            if let status = tab.status, b.status != status { return false }
            if let kind, b.kind != kind { return false }
            if let stars, b.rating != stars { return false }
            if !q.isEmpty {
                let hay = ([b.title, b.authorLine] + b.tags).joined(separator: " ")
                    .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
                if !hay.contains(q) { return false }
            }
            return true
        }
        return filtered.sorted { a, b in
            switch sort {
            case .recent: (a.book.lastOpenedAt ?? a.book.addedAt) > (b.book.lastOpenedAt ?? b.book.addedAt)
            case .added: a.book.addedAt > b.book.addedAt
            case .title: a.book.title.localizedStandardCompare(b.book.title) == .orderedAscending
            case .author: a.book.authorLine.localizedStandardCompare(b.book.authorLine) == .orderedAscending
            case .rating: (a.book.rating ?? 0, a.book.title) > (b.book.rating ?? 0, b.book.title)
            case .progress: a.book.progress > b.book.progress
            }
        }
    }

    var hasFilters: Bool { kind != nil || stars != nil || !query.isEmpty }

    func clearFilters() {
        kind = nil
        stars = nil
        query = ""
    }
}
