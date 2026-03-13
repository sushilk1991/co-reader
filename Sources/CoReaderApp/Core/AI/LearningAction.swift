enum LearningAction: String, CaseIterable, Identifiable, Sendable {
    case summarize
    case extractCode
    case explainVisuals
    case quizMe

    var id: String { rawValue }

    var title: String {
        switch self {
        case .summarize:
            "Summarize Focus"
        case .extractCode:
            "Generate Example"
        case .explainVisuals:
            "Explain Diagram"
        case .quizMe:
            "Quiz This Section"
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
            "Summarize the current reading focus in \(document.title) as a compact study-guide grounded only in the provided section context."
        case .extractCode:
            "Generate a practical code example from the current focus area in \(document.title), and explain how it connects to the text."
        case .explainVisuals:
            "If the current section of \(document.title) contains a diagram, chart, or workflow, explain it clearly and step by step."
        case .quizMe:
            "Create a short quiz from the current section of \(document.title) with answers hidden until the end."
        }
    }
}
