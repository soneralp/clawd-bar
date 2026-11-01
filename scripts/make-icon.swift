// Renders the Clawd Bar app icon as pixel art and writes an .iconset.
//
//   swift scripts/make-icon.swift <output.iconset> [preview.png]
//   iconutil -c icns <output.iconset> -o Resources/AppIcon.icns
//
// The icon is a 32×32 pixel grid drawn with nearest-neighbor scaling, so
// every size stays crisp.

import AppKit

let grid = 32

// Palette
let clear = NSColor.clear
func rgb(_ hex: UInt32) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
}
let palette: [Character: NSColor] = [
    "B": rgb(0x24201E),  // background
    "b": rgb(0x2E2926),  // background, lighter lower half
    "E": rgb(0x14110F),  // background edge
    "M": rgb(0x3B3532),  // menu bar strip
    "m": rgb(0x8E8783),  // menu bar items
    "o": rgb(0xD97757),  // Clawd body
    "h": rgb(0xEC9877),  // Clawd highlight
    "s": rgb(0xB35A3E),  // Clawd shade
    "d": rgb(0x1A1A1A),  // eyes
    "w": rgb(0xFFFFFF),  // eye glint
    "y": rgb(0xFFD60A),  // sparkle
    "g": rgb(0x30D158),  // status dot
    "S": rgb(0x1E1A18),  // ground shadow
]

/// Builds the 32×32 grid row by row.
func artwork() -> [[Character]] {
    var pixels = Array(repeating: Array(repeating: Character("."), count: grid), count: grid)

    // Rounded square with stepped corners.
    let insets = [4, 2, 1, 1]
    for y in 0..<grid {
        let fromTop = y, fromBottom = grid - 1 - y
        let inset = fromTop < insets.count ? insets[fromTop] : (fromBottom < insets.count ? insets[fromBottom] : 0)
        for x in inset..<(grid - inset) {
            let edge = y == 0 || y == grid - 1 || x == inset || x == grid - 1 - inset
            pixels[y][x] = edge ? "E" : (y >= 20 ? "b" : "B")
        }
    }

    // A miniature menu bar across the top, with a few status items and a
    // tiny Clawd on the right, the way the app sits in the real menu bar.
    for y in 3...6 {
        for x in 2...29 where pixels[y][x] != "E" && pixels[y][x] != "." { pixels[y][x] = "M" }
    }
    for x in [5, 6, 7, 10, 11, 14, 15, 16] { pixels[5][x] = "m" }
    let mini = ["ooo", "ooo", "o.o"]
    for (dy, row) in mini.enumerated() {
        for (dx, c) in row.enumerated() where c != "." { pixels[4 + dy][25 + dx] = c }
    }
    pixels[4][22] = "g"

    // Clawd: the 8×9 menu bar sprite at two grid pixels per sprite pixel.
    let sprite = [
        ".oooooo.",
        "oooooooo",
        "oodoodoo",
        "oooooooo",
        "oooooooo",
        "oooooooo",
        ".oooooo.",
        ".o....o.",
    ]
    let originX = 8, originY = 11
    for (sy, row) in sprite.enumerated() {
        for (sx, c) in row.enumerated() where c != "." {
            for dy in 0..<2 { for dx in 0..<2 { pixels[originY + sy * 2 + dy][originX + sx * 2 + dx] = c } }
        }
    }
    // Light from the top left: highlight the upper-left rim, shade the lower-right.
    func isBody(_ x: Int, _ y: Int) -> Bool { "od".contains(pixels[y][x]) }
    var shaded = pixels
    for y in originY..<(originY + 16) {
        for x in originX..<(originX + 16) where pixels[y][x] == "o" {
            if !isBody(x, y - 1) || !isBody(x - 1, y) { shaded[y][x] = "h" }
            else if !isBody(x, y + 1) || !isBody(x + 1, y) { shaded[y][x] = "s" }
        }
    }
    pixels = shaded
    // Eye glints.
    pixels[originY + 4][originX + 4] = "w"
    pixels[originY + 4][originX + 10] = "w"

    // Ground shadow under the feet.
    for x in 9...22 { pixels[27][x] = "S" }
    for x in 11...20 { pixels[28][x] = "S" }

    // Sparkles: Clawd at work.
    for (x, y) in [(5, 12), (4, 13), (6, 13), (5, 14), (26, 17), (27, 16)] { pixels[y][x] = "y" }
    return pixels
}

func render(_ pixels: [[Character]], size: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    let context = NSGraphicsContext(bitmapImageRep: rep)!
    context.shouldAntialias = false
    NSGraphicsContext.current = context
    // macOS icons leave a margin around the artwork (824 of 1024 points).
    let content = CGFloat(size) * 824 / 1024
    let margin = (CGFloat(size) - content) / 2
    let pixel = content / CGFloat(grid)
    for (y, row) in pixels.enumerated() {
        for (x, c) in row.enumerated() {
            guard let color = palette[c] else { continue }
            color.setFill()
            let rect = NSRect(x: margin + CGFloat(x) * pixel, y: CGFloat(size) - margin - CGFloat(y + 1) * pixel,
                              width: pixel, height: pixel).integral
            rect.fill()
        }
    }
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let arguments = CommandLine.arguments
guard arguments.count >= 2 else {
    FileHandle.standardError.write(Data("usage: make-icon.swift <output.iconset> [preview.png]\n".utf8))
    exit(1)
}
let iconset = URL(fileURLWithPath: arguments[1])
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
let pixels = artwork()
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let suffix = scale == 2 ? "@2x" : ""
        let data = render(pixels, size: points * scale).representation(using: .png, properties: [:])!
        try data.write(to: iconset.appendingPathComponent("icon_\(points)x\(points)\(suffix).png"))
    }
}
if arguments.count >= 3 {
    try render(pixels, size: 512).representation(using: .png, properties: [:])!
        .write(to: URL(fileURLWithPath: arguments[2]))
}
