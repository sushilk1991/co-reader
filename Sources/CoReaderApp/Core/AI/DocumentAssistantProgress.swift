/// Where an in-flight question currently is, for the chat panel's status row.
enum DocumentAssistantProgress: Equatable, Sendable {
    case extractingContext(PageScanProgress)
    case generating(model: String)

    var label: String {
        switch self {
        case let .extractingContext(progress):
            "Reading \(progress.label)…"
        case let .generating(model):
            "Waiting for \(model)…"
        }
    }
}
