import Foundation

enum EPUBLoaderError: LocalizedError {
    case missingContainer
    case missingPackagePath
    case missingPackageDocument
    case missingSpine
    case noRenderableSections
    case extractionFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingContainer:
            return "The EPUB is missing META-INF/container.xml."
        case .missingPackagePath:
            return "The EPUB container did not declare a package document."
        case .missingPackageDocument:
            return "The EPUB package document could not be opened."
        case .missingSpine:
            return "The EPUB did not expose a readable spine."
        case .noRenderableSections:
            return "The EPUB opened, but no readable XHTML sections were found."
        case let .extractionFailed(detail):
            return detail.isEmpty
                ? "The EPUB archive could not be extracted."
                : "The EPUB archive could not be extracted: \(detail)"
        }
    }
}
