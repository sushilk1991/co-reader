import Foundation

struct EPUBSection: Equatable, Identifiable, Sendable {
    let id: String
    let title: String
    let contentURL: URL
    let textContent: String
}
