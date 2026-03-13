import Foundation

protocol HTTPDataLoading: Sendable {
    func data(from url: URL) async throws -> (Data, URLResponse)
}
