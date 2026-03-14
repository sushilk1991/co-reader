import Foundation

struct EPUBBook: Equatable, Sendable {
    let title: String
    let rootURL: URL
    let sections: [EPUBSection]

    func sectionIndex(for navigatedURL: URL) -> Int? {
        let normalizedURL = normalizedSectionURL(for: navigatedURL)
        return sections.firstIndex { section in
            normalizedSectionURL(for: section.contentURL) == normalizedURL
        }
    }

    private func normalizedSectionURL(for url: URL) -> URL {
        guard var components = URLComponents(url: url.absoluteURL, resolvingAgainstBaseURL: false) else {
            return url.standardizedFileURL
        }

        components.fragment = nil
        components.query = nil
        return (components.url ?? url).standardizedFileURL
    }
}
