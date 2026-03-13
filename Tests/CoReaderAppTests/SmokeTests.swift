import Testing
@testable import CoReaderApp

@MainActor
@Test
func appModelHasExpectedLaunchCopy() {
    let appModel = AppModel()

    #expect(appModel.appTitle == "Co-Reader")
    #expect(appModel.statusHeadline.contains("initializing"))
    #expect(appModel.isLibraryVisible == false)
    #expect(appModel.isInspectorVisible == false)
    #expect(appModel.providerReadinessLabel.contains("AI"))
}
