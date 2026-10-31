import AppKit
import ClawdCore

/// Draws the 8×8 pixel-art Clawd mascot. The whole body takes the state's
/// color; only the eyes stay dark.
enum PixelIcon {
    /// Point size of the status item image.
    static let size: CGFloat = 18

    /// `o` body, `d` eye, anything else transparent.
    private static let awake = [
        ".oooooo.",
        "oooooooo",
        "oodooodo",
        "oooooooo",
        "oooooooo",
        "oooooooo",
        ".oooooo.",
        ".o....o.",
    ]

    /// Closed eyes for when no session is running.
    private static let asleep = [
        ".oooooo.",
        "oooooooo",
        "oooooooo",
        "oddooddo",
        "oooooooo",
        "oooooooo",
        ".oooooo.",
        ".o....o.",
    ]

    private static var cache: [IconState: NSImage] = [:]

    static func image(for state: IconState) -> NSImage {
        if let cached = cache[state] { return cached }
        let image = render(rows: state == .idle ? asleep : awake, body: Palette.color(for: state))
        image.accessibilityDescription = accessibilityLabel(for: state)
        cache[state] = image
        return image
    }

    private static func render(rows: [String], body: NSColor) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: true) { rect in
            let pixel = rect.width / CGFloat(rows.count)
            for (y, row) in rows.enumerated() {
                for (x, character) in row.enumerated() {
                    let color: NSColor
                    switch character {
                    case "o": color = body
                    case "d": color = Palette.eye
                    default: continue
                    }
                    color.setFill()
                    NSRect(x: CGFloat(x) * pixel, y: CGFloat(y) * pixel, width: pixel, height: pixel).fill()
                }
            }
            return true
        }
        image.isTemplate = false
        return image
    }

    private static func accessibilityLabel(for state: IconState) -> String {
        switch state {
        case .idle: "Clawd Bar: no sessions"
        case .done: "Clawd Bar: sessions finished"
        case .running: "Clawd Bar: sessions running"
        case .waiting: "Clawd Bar: a session needs you"
        }
    }
}
