import Testing
import WebKit
@testable import CoReaderApp

@MainActor
struct WeakScriptMessageProxyTests {
    /// `WKUserContentController` retains its handlers; registering through the proxy
    /// must leave the real handler free to deallocate.
    @Test
    func controllerDoesNotKeepTheRealHandlerAlive() {
        let controller = WKUserContentController()
        weak var weakHandler: RecordingHandler?
        let proxy: WeakScriptMessageProxy

        do {
            let handler = RecordingHandler()
            weakHandler = handler
            proxy = WeakScriptMessageProxy(target: handler)
            controller.add(proxy, name: "coreaderSelection")
        }

        #expect(weakHandler == nil)
        #expect(proxy.target == nil)
    }
}

@MainActor
private final class RecordingHandler: NSObject, WKScriptMessageHandler {
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {}
}
