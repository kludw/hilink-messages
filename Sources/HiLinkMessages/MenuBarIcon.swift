import AppKit

/// The menu bar icon: five signal bars, filled up to the current signal strength.
@MainActor
enum MenuBarIcon {
    private static var cache: [String: NSImage] = [:]

    /// - Parameters:
    ///   - level: signal strength, 0...5.
    ///   - isConnected: false draws all bars faint with a slash through them (no stick or no SIM).
    ///   - hasUnread: adds a dot in the top-left corner.
    static func image(level: Int, isConnected: Bool, hasUnread: Bool) -> NSImage {
        let level = isConnected ? min(max(level, 0), 5) : 0
        let key = "\(level)-\(isConnected)-\(hasUnread)"
        if let cached = cache[key] { return cached }

        let size = NSSize(width: 21, height: 15)
        let image = NSImage(size: size, flipped: false) { _ in
            let barWidth: CGFloat = 3
            let gap: CGFloat = 1.5
            for index in 0..<5 {
                let height = 3 + CGFloat(index) * 2.75
                let bar = NSRect(x: CGFloat(index) * (barWidth + gap), y: 0.5, width: barWidth, height: height)
                NSColor.black.withAlphaComponent(index < level ? 1 : 0.3).setFill()
                NSBezierPath(roundedRect: bar, xRadius: 0.8, yRadius: 0.8).fill()
            }

            if !isConnected {
                let slash = NSBezierPath()
                slash.move(to: NSPoint(x: 1.5, y: 13.5))
                slash.line(to: NSPoint(x: 19.5, y: 1))
                slash.lineWidth = 1.6
                slash.lineCapStyle = .round
                NSColor.black.setStroke()
                slash.stroke()
            }

            if hasUnread {
                NSColor.black.setFill()
                NSBezierPath(ovalIn: NSRect(x: 0, y: 9.5, width: 5.5, height: 5.5)).fill()
            }
            return true
        }
        // Template: macOS tints it for light and dark menu bars; the alpha values carry the shading.
        image.isTemplate = true
        image.accessibilityDescription = isConnected ? "Signal \(level) of 5" : "LTE stick not connected"
        cache[key] = image
        return image
    }
}
