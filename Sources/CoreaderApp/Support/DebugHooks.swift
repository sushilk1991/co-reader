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
        // The canvas grows to take in popovers that reach past the window's edge.
        let overlays = visible.filter { $0 !== window }.sorted { $0.orderedIndex > $1.orderedIndex }
        let canvas = overlays.reduce(window.frame) { $0.union($1.frame) }
        let width = Int(canvas.width), height = Int(canvas.height)
        let originX = window.frame.minX - canvas.minX, originY = window.frame.minY - canvas.minY
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
        base.setFillColor(NSColor(white: 0.5, alpha: 1).cgColor)
        base.fill(CGRect(x: 0, y: 0, width: width, height: height))
        if let image = render(window) {
            base.draw(image, in: CGRect(x: originX, y: originY, width: window.frame.width, height: window.frame.height))
        }
        // Sheets and popovers are windows of their own; they go on top once web content is in.
        func drawOverlays() {
            for w in overlays {
                guard let image = render(w) else { continue }
                base.draw(image, in: CGRect(x: w.frame.minX - canvas.minX, y: w.frame.minY - canvas.minY,
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
        let scale: CGFloat = 1
        let windowTop = canvas.maxY - window.frame.maxY
        for web in webs {
            let frame = web.convert(web.bounds, to: nil)
            let w = Int(frame.width * scale), h = Int(frame.height * scale)
            let originX = Int(originX + frame.minX), originY = Int(windowTop + window.frame.height - frame.maxY)
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
        // Into the application's event queue, as real events arrive, so event monitors and
        // the nested loops that track a drag both see them.
        NSApp.postEvent(event, atStart: false)
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
            // Spread over time, as a hand does it: gesture recognizers follow the events
            // across run-loop turns and ignore a drag that happens all at once.
            mouse(.leftMouseDown, n[0], n[1])
            let steps = 12
            for i in 1...steps {
                let t = Double(i) / Double(steps)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.03 * Double(i)) {
                    mouse(.leftMouseDragged, n[0] + (n[2] - n[0]) * t, n[1] + (n[3] - n[1]) * t)
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.03 * Double(steps + 2)) { mouse(.leftMouseUp, n[2], n[3]) }
        case "scroll" where n.count == 3:
            // `scroll x y dy`: moves the scroll view under that spot by dy points, a little
            // each frame as a trackpad would. Synthetic wheel events are ignored by
            // SwiftUI's scroll view, so the clip view is moved directly.
            guard let (window, point) = target(n[0], n[1]),
                  let scroller = window.contentView?.hitTest(point)?.enclosingScrollView else { return true }
            let frames = max(1, Int(abs(n[2]) / 40))
            for i in 0..<frames {
                DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) / 60) {
                    let clip = scroller.contentView
                    let flipped = scroller.documentView?.isFlipped ?? true
                    var origin = clip.bounds.origin
                    origin.y += (flipped ? 1 : -1) * n[2] / Double(frames)
                    clip.scroll(to: clip.constrainBoundsRect(NSRect(origin: origin, size: clip.bounds.size)).origin)
                    scroller.reflectScrolledClipView(clip)
                }
            }
        case "bench" where n.count == 3:
            // `bench x y dy`: scrolls down dy points and back in 40-point steps, laying out
            // and committing each step before the next, and logs how long the steps took.
            // Synchronous, so timer coalescing and App Nap cannot blur the numbers.
            guard let (window, point) = target(n[0], n[1]),
                  let scroller = window.contentView?.hitTest(point)?.enclosingScrollView else { return true }
            let clip = scroller.contentView
            let sign: Double = (scroller.documentView?.isFlipped ?? true) ? 1 : -1
            var times: [Double] = []
            for direction in [1.0, -1.0] {
                for _ in 0..<max(1, Int(n[2] / 40)) {
                    let start = DispatchTime.now().uptimeNanoseconds
                    var origin = clip.bounds.origin
                    origin.y += sign * direction * 40
                    clip.scroll(to: clip.constrainBoundsRect(NSRect(origin: origin, size: clip.bounds.size)).origin)
                    scroller.reflectScrolledClipView(clip)
                    window.layoutIfNeeded()
                    window.displayIfNeeded()
                    CATransaction.flush()
                    RunLoop.current.run(until: Date())   // lets SwiftUI's own observers run
                    times.append(Double(DispatchTime.now().uptimeNanoseconds - start) / 1e6)
                }
            }
            let sorted = times.sorted()
            let total = times.reduce(0, +)
            log(String(format: "bench steps=%d total=%.0fms p50=%.1f p95=%.1f max=%.1f over16=%d over33=%d", times.count, total,
                       sorted[sorted.count / 2], sorted[sorted.count * 95 / 100], sorted.last ?? 0,
                       times.filter { $0 > 16.7 }.count, times.filter { $0 > 33.3 }.count))
        case "type" where parts.count > 1:
            let window = NSApp.windows.first { $0.isVisible && $0.firstResponder is NSTextView } ?? mainWindow
            (window?.firstResponder as? NSTextView)?.insertText(parts[1], replacementRange: NSRange(location: NSNotFound, length: 0))
        case "key" where parts.count > 1:
            let codes: [String: (UInt16, String)] = ["return": (36, "\r"), "escape": (53, "\u{1b}"), "tab": (48, "\t"), "left": (123, "\u{F702}"), "right": (124, "\u{F703}"),
                                                     "up": (126, "\u{F700}"), "down": (125, "\u{F701}"), "delete": (51, "\u{7f}"), "space": (49, " ")]
            guard let (code, chars) = codes[parts[1]] else { return true }
            let window = NSApp.windows.filter { $0.isVisible }.min(by: { $0.orderedIndex < $1.orderedIndex }) ?? mainWindow
            for type in [NSEvent.EventType.keyDown, .keyUp] {
                if let event = NSEvent.keyEvent(with: type, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                                windowNumber: window?.windowNumber ?? 0, context: nil, characters: chars,
                                                charactersIgnoringModifiers: chars, isARepeat: false, keyCode: code) { NSApp.sendEvent(event) }
            }
        default:
            return false
        }
        return true
    }

    /// Logs every stretch where the main thread could not run for more than 20 ms:
    /// what a person feels as a stutter. A background thread pings the main queue.
    private static func watchForHitches() {
        let thread = Thread {
            while true {
                let sent = DispatchTime.now().uptimeNanoseconds
                let done = DispatchSemaphore(value: 0)
                DispatchQueue.main.async { done.signal() }
                done.wait()
                let ms = Double(DispatchTime.now().uptimeNanoseconds - sent) / 1e6
                if ms > 20 { log("hitch \(Int(ms)) ms") }
                Thread.sleep(forTimeInterval: 0.004)
            }
        }
        thread.qualityOfService = .userInteractive
        thread.start()
    }

    static func install(commands handler: @escaping (String) -> Void) {
        commandHandler = handler
        if environment["COREADER_HITCHES"] == "1" { watchForHitches() }
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
