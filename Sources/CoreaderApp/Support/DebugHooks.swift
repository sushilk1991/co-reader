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

    /// Captures the app's own main window. A process may always image its own windows, so
    /// this works without the Screen Recording permission. The function is hidden from the
    /// current SDK, hence the dynamic lookup.
    static func snapshot(to path: String) {
        typealias Fn = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?
        guard let window = NSApp.windows.filter({ $0.styleMask.contains(.titled) && $0.isVisible }).max(by: { $0.frame.width < $1.frame.width }),
              let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CGWindowListCreateImage") else { return log("shot: no window") }
        let create = unsafeBitCast(symbol, to: Fn.self)
        // .optionIncludingWindow = 1 << 3; .boundsIgnoreFraming = 1 << 0
        guard let image = create(.null, 1 << 3, UInt32(window.windowNumber), 1 << 0)?.takeRetainedValue() else { return log("shot: capture failed") }
        let width = image.width, height = image.height
        func context(_ w: Int, _ h: Int) -> CGContext {
            CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        }
        let base = context(width, height)
        base.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        func find(_ v: NSView) -> [WKWebView] { (v as? WKWebView).map { [$0] } ?? v.subviews.flatMap(find) }
        let webs = find(window.contentView!).filter { !$0.isHiddenOrHasHiddenAncestor && $0.frame.width > 1 }
        func finish() {
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
        timer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { _ in
            MainActor.assumeIsolated {
                guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { return }
                let lines = text.split(separator: "\n").map(String.init)
                while offset < lines.count {
                    let line = lines[offset]
                    offset += 1
                    log("command: \(line)")
                    if line.hasPrefix("shot ") { snapshot(to: String(line.dropFirst(5))) } else { commandHandler?(line) }
                }
            }
        }
    }
}
