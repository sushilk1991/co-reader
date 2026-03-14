import Foundation
import Testing
@testable import CoReaderApp

struct LearningActionTests {
    @Test
    func quickActionsGenerateFocusedPrompts() {
        let document = ReaderDocument(fileURL: URL(fileURLWithPath: "/tmp/Advanced Algorithms.pdf"))

        #expect(LearningAction.summarize.prompt(for: document, scope: .focus).contains("Advanced Algorithms"))
        #expect(LearningAction.extractCode.prompt(for: document, scope: .focus).contains("practical code example"))
        #expect(LearningAction.explainVisuals.prompt(for: document, scope: .focus).contains("diagram"))
        #expect(LearningAction.quizMe.prompt(for: document, scope: .focus).contains("short quiz"))
    }

    @Test
    func summarizePromptExpandsWhenDocumentScopeIsSelected() {
        let document = ReaderDocument(fileURL: URL(fileURLWithPath: "/tmp/Advanced Algorithms.pdf"))

        #expect(LearningAction.summarize.prompt(for: document, scope: .document).contains("whole document"))
        #expect(LearningAction.summarize.prompt(for: document, scope: .selection).contains("selected passage"))
    }
}
