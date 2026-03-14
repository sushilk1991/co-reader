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

    func prompt(for document: ReaderDocument, scope: DocumentQueryScope) -> String {
        switch self {
        case .summarize:
            switch scope {
            case .selection:
                "Summarize the selected passage in \(document.title) as a compact study-guide grounded only in the provided selection context."
            case .focus:
                "Summarize the current reading focus in \(document.title) as a compact study-guide grounded only in the provided section context."
            case .document:
                "Summarize the whole document \(document.title) as a compact study-guide, synthesizing chapter-by-chapter ideas only from the provided document sweep excerpts."
            }
        case .extractCode:
            switch scope {
            case .selection:
                "Generate a practical code example from the selected passage in \(document.title), and explain how it connects to the text."
            case .focus:
                "Generate a practical code example from the current focus area in \(document.title), and explain how it connects to the text."
            case .document:
                "Generate a practical code example that captures a core idea from the whole document \(document.title), and explain which document sweep excerpts support it."
            }
        case .explainVisuals:
            "If the current section of \(document.title) contains a diagram, chart, or workflow, explain it clearly and step by step."
        case .quizMe:
            switch scope {
            case .selection:
                "Create a short quiz from the selected passage in \(document.title) with answers hidden until the end."
            case .focus:
                "Create a short quiz from the current section of \(document.title) with answers hidden until the end."
            case .document:
                "Create a short quiz covering the whole document \(document.title), using only the current document sweep excerpts and hiding answers until the end."
            }
        }
    }
}
