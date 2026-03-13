import Testing
@testable import CoReaderApp

@MainActor
@Test
func appModelHasExpectedLaunchCopy() {
    let appModel = AppModel()

    #expect(appModel.appTitle == "Co-Reader")
    #expect(appModel.statusHeadline.contains("initializing"))
}
