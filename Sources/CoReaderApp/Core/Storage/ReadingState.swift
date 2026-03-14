import Foundation

struct ReadingState: Codable, Sendable {
    var documentURLs: [URL]
    var activeDocumentURL: URL?
    var positions: [String: Int]
}
