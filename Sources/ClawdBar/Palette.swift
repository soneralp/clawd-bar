import AppKit
import ClawdCore

/// Brand colors used by the icon and the menu rows.
enum Palette {
    static let running = NSColor(srgbHex: 0xD97757)
    static let waiting = NSColor(srgbHex: 0xFFD60A)
    static let done = NSColor(srgbHex: 0x30D158)
    static let idle = NSColor(srgbHex: 0x8E8E93)
    static let eye = NSColor(srgbHex: 0x1A1A1A)

    static func color(for state: IconState) -> NSColor {
        switch state {
        case .idle: idle
        case .done: done
        case .running: running
        case .waiting: waiting
        }
    }

    static func color(for state: SessionState) -> NSColor {
        switch state {
        case .running: running
        case .waiting: waiting
        case .done: done
        }
    }
}

extension NSColor {
    convenience init(srgbHex hex: UInt32) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}
