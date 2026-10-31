import AppKit
import ClawdCore

/// Draws the 8×9 pixel-art Clawd mascot. The whole body takes the state's
/// color; only the eyes stay dark. While a session is working, `workingFrames`
/// make Clawd hop in place and glance around.
enum PixelIcon {
    /// Every sprite pixel is exactly 2 pt, so pixels land on whole device
    /// pixels and stay crisp.
    static let pixelSize: CGFloat = 2
    static let columns = 8
    static let rows = 9
    static var size: NSSize { NSSize(width: CGFloat(columns) * pixelSize, height: CGFloat(rows) * pixelSize) }

    /// Number of frames in the working loop.
    static var workingFrameCount: Int { workingFrames.count }

    // `o` body, `d` eye, anything else transparent. The top row is blank so
    // the hop frames have room to move up.

    private static let standing = [
        "........",
        ".oooooo.",
        "oooooooo",
        "oodoodoo",
        "oooooooo",
        "oooooooo",
        "oooooooo",
        ".oooooo.",
        ".o....o.",
    ]

    private static let asleep = [
        "........",
        ".oooooo.",
        "oooooooo",
        "oooooooo",
        "oddoddoo",
        "oooooooo",
        "oooooooo",
        ".oooooo.",
        ".o....o.",
    ]

    /// Stand, hop and land again while looking left, then the same looking right.
    private static let workingFrames: [[String]] = [
        sprite(eyes: "odoodooo", lifted: false),
        sprite(eyes: "odoodooo", lifted: true),
        sprite(eyes: "ooodoodo", lifted: false),
        sprite(eyes: "ooodoodo", lifted: true),
    ]

    private static func sprite(eyes: String, lifted: Bool) -> [String] {
        let body = [".oooooo.", "oooooooo", eyes, "oooooooo", "oooooooo", "oooooooo", ".oooooo."]
        return lifted
            ? body + ["..o..o..", "........"]
            : ["........"] + body + [".o....o."]
    }

    private struct CacheKey: Hashable {
        let state: IconState
        let frame: Int?
    }

    private static var cache: [CacheKey: NSImage] = [:]

    /// The still image for `state`.
    static func image(for state: IconState) -> NSImage {
        cachedImage(CacheKey(state: state, frame: nil)) {
            state == .idle ? asleep : standing
        }
    }

    /// One frame of the working loop, colored for `state`.
    static func workingImage(for state: IconState, frame: Int) -> NSImage {
        let index = frame % workingFrames.count
        return cachedImage(CacheKey(state: state, frame: index)) { workingFrames[index] }
    }

    private static func cachedImage(_ key: CacheKey, sprite: () -> [String]) -> NSImage {
        if let cached = cache[key] { return cached }
        let image = render(rows: sprite(), body: Palette.color(for: key.state))
        image.accessibilityDescription = accessibilityLabel(for: key.state)
        cache[key] = image
        return image
    }

    private static func render(rows: [String], body: NSColor) -> NSImage {
        let image = NSImage(size: size, flipped: true) { _ in
            NSGraphicsContext.current?.shouldAntialias = false
            for (y, row) in rows.enumerated() {
                for (x, character) in row.enumerated() {
                    let color: NSColor
                    switch character {
                    case "o": color = body
                    case "d": color = Palette.eye
                    default: continue
                    }
                    color.setFill()
                    NSRect(x: CGFloat(x) * pixelSize, y: CGFloat(y) * pixelSize,
                           width: pixelSize, height: pixelSize).fill()
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
