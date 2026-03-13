import Observation

@MainActor
@Observable
final class AppModel {
    let appTitle = "Co-Reader"
    let statusHeadline = "Local AI integrations are initializing."
    let statusDetail = "Provider discovery ships in the next checkpoint."
}
