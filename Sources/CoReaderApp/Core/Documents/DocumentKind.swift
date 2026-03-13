enum DocumentKind: String, Equatable, Sendable {
    case pdf
    case epub
    case unknown

    var displayName: String {
        rawValue.uppercased()
    }
}
