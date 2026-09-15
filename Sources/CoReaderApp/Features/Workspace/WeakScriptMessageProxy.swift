import WebKit

/// Stands between `WKUserContentController` and the real handler.
///
/// The controller retains its message handlers strongly and never lets go until
/// the handler is removed by name, so registering a coordinator directly kept it,
/// and every closure it held, alive for as long as the web view lived.
@MainActor
final class WeakScriptMessageProxy: NSObject, WKScriptMessageHandler {
    private(set) weak var target: (any WKScriptMessageHandler)?

    init(target: any WKScriptMessageHandler) {
        self.target = target
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(userContentController, didReceive: message)
    }
}
