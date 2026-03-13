enum LearningAction: String, CaseIterable, Identifiable, Sendable {
    case summarize
    case extractCode
    case explainVisuals
    case quizMe

    var id: String { rawValue }

    var title: String {
        switch self {
        case .summarize:
            "Summarize"
        case .extractCode:
            "Generate Code"
        case .explainVisuals:
            "Explain Diagram"
        case .quizMe:
            "Quiz Me"
        }
    }

    var systemImage: String {
        switch self {
        case .summarize:
            "text.alignleft"
        case .extractCode:
            "curlybraces"
        case .explainVisuals:
            "eye"
        case .quizMe:
            "questionmark.bubble"
        }
    }

    func prompt(for document: ReaderDocument) -> String {
        switch self {
        case .summarize:
            "Summarize the most important ideas in \(document.title) in a compact study-guide format."
        case .extractCode:
            "Generate a code example based on the key ideas in \(document.title), and explain how it connects to the document."
        case .explainVisuals:
            "If this document contains a diagram, chart, or visual workflow, explain the most important visual in \(document.title) clearly and step by step."
        case .quizMe:
            "Create a short quiz from \(document.title) with answers hidden until the end."
        }
    }
}
