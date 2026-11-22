import AppKit
import WebKit

/// Development aids for running the app unattended (never active in normal use):
/// `COREADER_OFFSCREEN=1` parks windows far off-screen so the app can be captured with
/// `screencapture -l` without ever appearing on the display; `COREADER_DEBUG_LOG=<file>`
/// receives a line per notable event; `COREADER_COMMANDS=<file>` is polled for one-line
/// commands that drive the UI.
@MainActor
enum DebugHooks {
    static let environment = ProcessInfo.processInfo.environment
    static var isOffscreen: Bool { environment["COREADER_OFFSCREEN"] == "1" }
    private static var commandHandler: ((String) -> Void)?
    private static var timer: Timer?
    private static var offset = 0
    private static var parked: Set<Int> = []

    /// Captures the app's main window with its sheets and popovers by asking the views to
    /// draw themselves. Nothing is read from the screen, so it needs no Screen Recording
    /// permission and works while the screen is locked.
    static func snapshot(to path: String) {
        let visible = NSApp.windows.filter { $0.isVisible && $0.frame.width > 40 }
        guard let window = visible.filter({ $0.styleMask.contains(.titled) && $0.sheetParent == nil })
            .max(by: { $0.frame.width < $1.frame.width }) else { return log("shot: no window") }
        let width = Int(window.frame.width), height = Int(window.frame.height)
        func context(_ w: Int, _ h: Int) -> CGContext {
            CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        }
        func render(_ w: NSWindow) -> CGImage? {
            guard let view = w.contentView?.superview ?? w.contentView,
                  let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return nil }
            view.cacheDisplay(in: view.bounds, to: rep)
            return rep.cgImage
        }
        let base = context(width, height)
        if let image = render(window) { base.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height)) }
        // Sheets and popovers are windows of their own; they go on top once web content is in.
        let overlays = visible.filter { $0 !== window }.sorted { $0.orderedIndex > $1.orderedIndex }
        func drawOverlays() {
            for w in overlays {
                guard let image = render(w) else { continue }
                base.draw(image, in: CGRect(x: w.frame.minX - window.frame.minX, y: w.frame.minY - window.frame.minY,
                                            width: w.frame.width, height: w.frame.height))
            }
        }
        func find(_ v: NSView) -> [WKWebView] { (v as? WKWebView).map { [$0] } ?? v.subviews.flatMap(find) }
        let webs = find(window.contentView!).filter { !$0.isHiddenOrHasHiddenAncestor && $0.frame.width > 1 }
        func finish() {
            drawOverlays()
            if let out = base.makeImage() {
                try? NSBitmapImageRep(cgImage: out).representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
            }
            log("shot: \(path) \(width)x\(height)")
        }
        var remaining = webs.count
        if remaining == 0 { return finish() }
        // Web content lives in another process and is missing from the window image, so it
        // is fetched separately and laid in wherever the window shows the bare page colour
        // (anything the app draws over the page stays on top).
        let scale = CGFloat(width) / window.frame.width
        for web in webs {
            let frame = web.convert(web.bounds, to: nil)
            let w = Int(frame.width * scale), h = Int(frame.height * scale)
            let originX = Int(frame.minX * scale), originY = Int((window.frame.height - frame.maxY) * scale)
            web.takeSnapshot(with: nil) { snap, _ in
                MainActor.assumeIsolated {
                    if let cg = snap?.cgImage(forProposedRect: nil, context: nil, hints: nil), w > 0, h > 0,
                       let pixels = base.data?.assumingMemoryBound(to: UInt8.self) {
                        let top = context(w, h)
                        top.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
                        let t = top.data!.assumingMemoryBound(to: UInt8.self)
                        let keyAt = ((originY + h / 2) * width + min(originX + w - 2, width - 1)) * 4
                        let key = (Int(pixels[keyAt]), Int(pixels[keyAt + 1]), Int(pixels[keyAt + 2]))
                        for y in 0..<h where originY + y < height {
                            for x in 0..<w where originX + x < width {
                                let b = ((originY + y) * width + originX + x) * 4, i = (y * w + x) * 4
                                let a = Int(t[i + 3])
                                guard a > 0, abs(Int(pixels[b]) - key.0) + abs(Int(pixels[b + 1]) - key.1) + abs(Int(pixels[b + 2]) - key.2) < 6 else { continue }
                                for c in 0..<3 { pixels[b + c] = UInt8(min(255, Int(t[i + c]) + Int(pixels[b + c]) * (255 - a) / 255)) }
                            }
                        }
                    }
                    remaining -= 1
                    if remaining == 0 { finish() }
                }
            }
        }
    }

    static func log(_ message: @autoclosure () -> String) {
        guard let path = environment["COREADER_DEBUG_LOG"] else { return }
        let line = message() + "\n"
        if let handle = FileHandle(forWritingAtPath: path) {
            handle.seekToEndOfFile()
            handle.write(Data(line.utf8))
            try? handle.close()
        } else {
            try? line.write(toFile: path, atomically: true, encoding: .utf8)
        }
    }

    // MARK: Synthetic input

    /// The app's main window, whose top-left corner is the origin for input commands.
    private static var mainWindow: NSWindow? {
        NSApp.windows.filter { $0.isVisible && $0.styleMask.contains(.titled) && $0.sheetParent == nil }
            .max(by: { $0.frame.width < $1.frame.width })
    }

    /// Topmost window (sheet, popover or main) under a point given in main-window
    /// coordinates with a top-left origin, and the point in that window's own coordinates.
    private static func target(_ x: Double, _ y: Double) -> (NSWindow, NSPoint)? {
        guard let main = mainWindow else { return nil }
        let screen = NSPoint(x: main.frame.minX + x, y: main.frame.maxY - y)
        let candidates = NSApp.windows.filter { $0.isVisible && $0.frame.contains(screen) }
            .sorted { ($0 === main ? 1 : 0, $0.orderedIndex) < ($1 === main ? 1 : 0, $1.orderedIndex) }
        guard let window = candidates.first else { return nil }
        return (window, NSPoint(x: screen.x - window.frame.minX, y: screen.y - window.frame.minY))
    }

    private static func mouse(_ type: NSEvent.EventType, _ x: Double, _ y: Double, clicks: Int = 1) {
        guard let (window, point) = target(x, y),
              let event = NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                             windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: clicks, pressure: 1) else { return }
        window.sendEvent(event)
    }

    /// `click x y`, `dclick x y`, `rclick x y`, `drag x1 y1 x2 y2`, `move x y`, `type text`,
    /// `key return|escape|tab|left|right|up|down|delete|space`. Returns false for other commands.
    private static func input(_ line: String) -> Bool {
        let parts = line.split(separator: " ", maxSplits: 1).map(String.init)
        let n = (parts.count > 1 ? parts[1] : "").split(separator: " ").compactMap { Double($0) }
        switch parts[0] {
        case "click" where n.count == 2:
            mouse(.mouseMoved, n[0], n[1]); mouse(.leftMouseDown, n[0], n[1]); mouse(.leftMouseUp, n[0], n[1])
        case "dclick" where n.count == 2:
            mouse(.leftMouseDown, n[0], n[1]); mouse(.leftMouseUp, n[0], n[1])
            mouse(.leftMouseDown, n[0], n[1], clicks: 2); mouse(.leftMouseUp, n[0], n[1], clicks: 2)
        case "rclick" where n.count == 2:
            mouse(.rightMouseDown, n[0], n[1]); mouse(.rightMouseUp, n[0], n[1])
        case "move" where n.count == 2:
            mouse(.mouseMoved, n[0], n[1])
        case "drag" where n.count == 4:
            mouse(.leftMouseDown, n[0], n[1])
            for i in 1...8 {
                let t = Double(i) / 8
                mouse(.leftMouseDragged, n[0] + (n[2] - n[0]) * t, n[1] + (n[3] - n[1]) * t)
            }
            mouse(.leftMouseUp, n[2], n[3])
        case "type" where parts.count > 1:
            let window = NSApp.windows.first { $0.isVisible && $0.firstResponder is NSTextView } ?? mainWindow
            (window?.firstResponder as? NSTextView)?.insertText(parts[1], replacementRange: NSRange(location: NSNotFound, length: 0))
        case "key" where parts.count > 1:
            let codes: [String: (UInt16, String)] = ["return": (36, "\r"), "escape": (53, "\u{1b}"), "tab": (48, "\t"), "left": (123, ""), "right": (124, ""),
                                                     "up": (126, ""), "down": (125, ""), "delete": (51, "\u{7f}"), "space": (49, " ")]
            guard let (code, chars) = codes[parts[1]] else { return true }
            let window = NSApp.windows.filter { $0.isVisible }.min(by: { $0.orderedIndex < $1.orderedIndex }) ?? mainWindow
            for type in [NSEvent.EventType.keyDown, .keyUp] {
                if let event = NSEvent.keyEvent(with: type, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                                windowNumber: window?.windowNumber ?? 0, context: nil, characters: chars,
                                                charactersIgnoringModifiers: chars, isARepeat: false, keyCode: code) { window?.sendEvent(event) }
            }
        default:
            return false
        }
        return true
    }

    static func install(commands handler: @escaping (String) -> Void) {
        commandHandler = handler
        if isOffscreen {
            NSApp.setActivationPolicy(.accessory)
            // Poll rather than observe: window notifications carry non-Sendable payloads.
            Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
                MainActor.assumeIsolated {
                    for window in NSApp.windows where !parked.contains(window.windowNumber) && window.styleMask.contains(.titled) && window.isVisible {
                        parked.insert(window.windowNumber)
                        if let size = environment["COREADER_WINDOW_SIZE"]?.split(separator: "x").compactMap({ Double($0) }), size.count == 2 {
                            window.setContentSize(NSSize(width: size[0], height: size[1]))
                        }
                        window.setFrameOrigin(NSPoint(x: -20000, y: 100))
                    }
                }
            }
        }
        guard let path = environment["COREADER_COMMANDS"] else { return }
        let poll = Timer(timeInterval: 0.3, repeats: true) { _ in
            MainActor.assumeIsolated {
                guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { return }
                let lines = text.split(separator: "\n").map(String.init)
                while offset < lines.count {
                    let line = lines[offset]
                    offset += 1
                    log("command: \(line)")
                    if line.hasPrefix("shot ") { snapshot(to: String(line.dropFirst(5))) }
                    else if !input(line) { commandHandler?(line) }
                }
            }
        }
        // Common modes, so commands keep flowing while a sheet or menu is up.
        RunLoop.main.add(poll, forMode: .common)
        timer = poll
    }
}
