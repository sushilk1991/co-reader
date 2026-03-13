import Foundation

struct URLSessionHTTPClient: HTTPDataLoading {
    func data(from url: URL) async throws -> (Data, URLResponse) {
        try await URLSession.shared.data(from: url)
    }
}
