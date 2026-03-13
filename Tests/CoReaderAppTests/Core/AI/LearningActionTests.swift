import Foundation
import Testing
@testable import CoReaderApp

struct LearningActionTests {
    @Test
    func quickActionsGenerateFocusedPrompts() {
        let document = ReaderDocument(fileURL: URL(fileURLWithPath: "/tmp/Advanced Algorithms.pdf"))

        #expect(LearningAction.summarize.prompt(for: document).contains("Advanced Algorithms"))
        #expect(LearningAction.extractCode.prompt(for: document).contains("practical code example"))
        #expect(LearningAction.explainVisuals.prompt(for: document).contains("diagram"))
        #expect(LearningAction.quizMe.prompt(for: document).contains("short quiz"))
    }
}
