enum DocumentQueryScope: String, CaseIterable, Identifiable, Sendable {
    case selection
    case focus
    case document

    var id: String { rawValue }

    var title: String {
        switch self {
        case .selection:
            "Selection"
        case .focus:
            "Focus"
        case .document:
            "Document"
        }
    }

    var detail: String {
        switch self {
        case .selection:
            "Ground the answer in the highlighted passage and its nearby context."
        case .focus:
            "Use the visible page or current chapter so the reply stays anchored to what you are reading."
        case .document:
            "Sweep the strongest chunks across the book and synthesize them without sending the entire file at once."
        }
    }

    var contextHeading: String {
        switch self {
        case .selection:
            "Selection"
        case .focus:
            "Focused Reading"
        case .document:
            "Document Sweep"
        }
    }
}
