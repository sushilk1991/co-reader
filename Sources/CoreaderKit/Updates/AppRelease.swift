import Foundation

/// A dotted version ("1.0.2", "v1.10"), compared number by number: 1.10 is newer than 1.9.
public struct AppVersion: Comparable, Sendable, CustomStringConvertible {
    public let parts: [Int]

    public init?(_ text: String) {
        var trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("v") || trimmed.hasPrefix("V") { trimmed.removeFirst() }
        let numbers = trimmed.split(separator: ".", omittingEmptySubsequences: false).map { Int($0) }
        guard !numbers.isEmpty, numbers.allSatisfy({ $0 != nil && $0! >= 0 }) else { return nil }
        parts = numbers.map { $0! }
    }

    public var description: String { parts.map(String.init).joined(separator: ".") }

    public static func == (a: AppVersion, b: AppVersion) -> Bool { !(a < b) && !(b < a) }

    public static func < (a: AppVersion, b: AppVersion) -> Bool {
        for i in 0..<max(a.parts.count, b.parts.count) {
            let x = i < a.parts.count ? a.parts[i] : 0, y = i < b.parts.count ? b.parts[i] : 0
            if x != y { return x < y }
        }
        return false
    }
}

/// One published build, as GitHub describes a release.
public struct AppRelease: Sendable, Equatable {
    public var version: AppVersion
    public var notes: String
    /// The release's page, for people who would rather download it themselves.
    public var page: URL
    /// GitHub's API address of the disk image. Unlike the browser link it also works for
    /// a private repository, given a token.
    public var asset: URL
    public var assetName: String
    public var size: Int

    /// The release in GitHub's "latest release" JSON, or nil when it is a draft, a
    /// pre-release, has no readable version, or carries no disk image.
    public static func parse(gitHubJSON data: Data) -> AppRelease? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              object["draft"] as? Bool != true, object["prerelease"] as? Bool != true,
              let tag = object["tag_name"] as? String, let version = AppVersion(tag),
              let pageText = object["html_url"] as? String, let page = URL(string: pageText), page.scheme == "https",
              let assets = object["assets"] as? [[String: Any]] else { return nil }
        for item in assets {
            guard let name = item["name"] as? String, name.lowercased().hasSuffix(".dmg"),
                  let text = item["url"] as? String, let url = URL(string: text), url.scheme == "https" else { continue }
            return AppRelease(version: version, notes: (object["body"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
                              page: page, asset: url, assetName: name, size: item["size"] as? Int ?? 0)
        }
        return nil
    }
}
