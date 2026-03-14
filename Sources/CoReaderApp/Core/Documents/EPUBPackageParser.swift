import AppKit
import Foundation

struct EPUBPackageParser {
    func packagePath(from containerXML: Data) throws -> String {
        let document = try XMLDocument(data: containerXML)
        guard let rootfile = try document.nodes(forXPath: "//*[local-name()='rootfile']").first as? XMLElement,
              let packagePath = rootfile.attribute(forName: "full-path")?.stringValue,
              !packagePath.isEmpty else {
            throw EPUBLoaderError.missingPackagePath
        }

        return packagePath
    }

    func makeBook(extractedRootURL: URL, fallbackTitle: String) throws -> EPUBBook {
        let containerURL = extractedRootURL
            .appending(path: "META-INF", directoryHint: .isDirectory)
            .appending(path: "container.xml")
        guard FileManager.default.fileExists(atPath: containerURL.path()) else {
            throw EPUBLoaderError.missingContainer
        }

        let packagePath = try packagePath(from: Data(contentsOf: containerURL))
        let packageURL = resolvedFileURL(for: packagePath, relativeTo: extractedRootURL)
        guard FileManager.default.fileExists(atPath: packageURL.path()) else {
            throw EPUBLoaderError.missingPackageDocument
        }

        let packageDocument = try XMLDocument(data: Data(contentsOf: packageURL))
        let packageDirectory = packageURL.deletingLastPathComponent()
        let manifest = try manifestItems(from: packageDocument)
        let spine = try spineItemIdentifiers(from: packageDocument)
        guard !spine.isEmpty else {
            throw EPUBLoaderError.missingSpine
        }

        let title = metadataTitle(from: packageDocument) ?? fallbackTitle
        let sections = try spine.compactMap { itemIdentifier -> EPUBSection? in
            guard let item = manifest[itemIdentifier] else {
                return nil
            }

            let lowercasedHref = item.href.lowercased()
            guard item.mediaType.contains("html") ||
                    lowercasedHref.hasSuffix(".xhtml") ||
                    lowercasedHref.hasSuffix(".html") ||
                    lowercasedHref.hasSuffix(".htm") else {
                return nil
            }

            let sectionURL = resolvedFileURL(for: item.href, relativeTo: packageDirectory)
            let sectionData = try Data(contentsOf: sectionURL)
            let (html, usedEncoding) = try decodedHTML(from: sectionData)
            let plainText = plainText(from: sectionData, encoding: usedEncoding, fallbackHTML: html)

            return EPUBSection(
                id: itemIdentifier,
                title: sectionTitle(from: html, fallbackURL: sectionURL),
                contentURL: sectionURL,
                textContent: plainText
            )
        }
        guard !sections.isEmpty else {
            throw EPUBLoaderError.noRenderableSections
        }

        return EPUBBook(title: title, rootURL: extractedRootURL, sections: sections)
    }

    private func resolvedFileURL(for path: String, relativeTo baseURL: URL) -> URL {
        baseURL
            .appending(path: path.removingPercentEncoding ?? path)
            .standardizedFileURL
    }

    private func manifestItems(from document: XMLDocument) throws -> [String: (href: String, mediaType: String)] {
        try document.nodes(forXPath: "//*[local-name()='manifest']/*[local-name()='item']")
            .compactMap { node -> (String, (href: String, mediaType: String))? in
                guard let element = node as? XMLElement,
                      let identifier = element.attribute(forName: "id")?.stringValue,
                      let href = element.attribute(forName: "href")?.stringValue else {
                    return nil
                }

                let mediaType = element.attribute(forName: "media-type")?.stringValue ?? ""
                return (identifier, (href: href, mediaType: mediaType))
            }
            .reduce(into: [:]) { partialResult, item in
                partialResult[item.0] = item.1
            }
    }

    private func spineItemIdentifiers(from document: XMLDocument) throws -> [String] {
        try document.nodes(forXPath: "//*[local-name()='spine']/*[local-name()='itemref']")
            .compactMap { node in
                (node as? XMLElement)?
                    .attribute(forName: "idref")?
                    .stringValue
            }
    }

    private func metadataTitle(from document: XMLDocument) -> String? {
        guard let titleNode = try? document.nodes(forXPath: "//*[local-name()='metadata']/*[local-name()='title']").first as? XMLElement else {
            return nil
        }

        return normalized(titleNode.stringValue)
    }

    private func decodedHTML(from htmlData: Data) throws -> (html: String, encoding: String.Encoding) {
        if let declaredEncoding = declaredEncoding(from: htmlData),
           let html = String(data: htmlData, encoding: declaredEncoding) {
            return (html, declaredEncoding)
        }

        if let html = String(data: htmlData, encoding: .utf8) {
            return (html, .utf8)
        }

        if let html = String(data: htmlData, encoding: .windowsCP1252) {
            return (html, .windowsCP1252)
        }

        throw EPUBLoaderError.noRenderableSections
    }

    private func declaredEncoding(from htmlData: Data) -> String.Encoding? {
        let sniffedData = htmlData.prefix(512)
        guard let declaration = String(data: sniffedData, encoding: .ascii) else {
            return nil
        }

        let patterns = [
            #"(?i)encoding\s*=\s*["']([^"']+)["']"#,
            #"(?i)charset\s*=\s*["']?([^"'>\s]+)["']?"#
        ]

        for pattern in patterns {
            guard let encodingName = firstMatch(in: declaration, pattern: pattern)?
                .trimmingCharacters(in: .whitespacesAndNewlines) else {
                continue
            }

            let convertedEncoding = CFStringConvertIANACharSetNameToEncoding(encodingName as CFString)
            guard convertedEncoding != kCFStringEncodingInvalidId else {
                continue
            }

            return String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(convertedEncoding))
        }

        return nil
    }

    private func plainText(from htmlData: Data, encoding: String.Encoding, fallbackHTML: String) -> String {
        let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
            .documentType: NSAttributedString.DocumentType.html,
            .characterEncoding: encoding.rawValue
        ]

        if let attributedString = try? NSAttributedString(
            data: htmlData,
            options: options,
            documentAttributes: nil
        ) {
            return normalizedText(attributedString.string)
        }

        return normalizedText(
            fallbackHTML
                .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        )
    }

    private func sectionTitle(from html: String, fallbackURL: URL) -> String {
        if let title = firstMatch(in: html, pattern: "(?is)<title[^>]*>(.*?)</title>") {
            let normalizedTitle = normalized(title.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression))
            if let normalizedTitle, !normalizedTitle.isEmpty {
                return normalizedTitle
            }
        }

        if let heading = firstMatch(in: html, pattern: "(?is)<h[1-3][^>]*>(.*?)</h[1-3]>") {
            let normalizedHeading = normalized(heading.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression))
            if let normalizedHeading, !normalizedHeading.isEmpty {
                return normalizedHeading
            }
        }

        return fallbackURL.deletingPathExtension().lastPathComponent
            .replacingOccurrences(of: "[-_]+", with: " ", options: .regularExpression)
            .capitalized
    }

    private func firstMatch(in value: String, pattern: String) -> String? {
        guard let expression = try? NSRegularExpression(pattern: pattern),
              let match = expression.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)),
              let range = Range(match.range(at: 1), in: value) else {
            return nil
        }

        return String(value[range])
    }

    private func normalizedText(_ value: String) -> String {
        normalized(value) ?? ""
    }

    private func normalized(_ value: String?) -> String? {
        guard let value else {
            return nil
        }

        let normalizedValue = value
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return normalizedValue.isEmpty ? nil : normalizedValue
    }
}
