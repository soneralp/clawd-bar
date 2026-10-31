import AppKit
import ClawdCore

/// A two-line menu row: status dot, project name and detail, elapsed time.
/// Clicking it brings Warp to the front.
final class SessionRowView: NSView {
    static let width: CGFloat = 320
    static let height: CGFloat = 40

    private let onClick: () -> Void
    private var isHighlighted = false {
        didSet { needsDisplay = true }
    }

    init(row: SessionRow, onClick: @escaping () -> Void) {
        self.onClick = onClick
        super.init(frame: NSRect(x: 0, y: 0, width: Self.width, height: Self.height))
        build(row)
        setAccessibilityRole(.menuItem)
        setAccessibilityLabel("\(row.displayName), \(row.detail), \(row.timeText)")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func draw(_ dirtyRect: NSRect) {
        guard isHighlighted else { return }
        NSColor.selectedContentBackgroundColor.withAlphaComponent(0.25).setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 5, dy: 1), xRadius: 4, yRadius: 4).fill()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self
        ))
    }

    override func mouseEntered(with event: NSEvent) { isHighlighted = true }
    override func mouseExited(with event: NSEvent) { isHighlighted = false }

    override func mouseUp(with event: NSEvent) {
        isHighlighted = false
        enclosingMenuItem?.menu?.cancelTracking()
        onClick()
    }

    // MARK: - Layout

    private func build(_ row: SessionRow) {
        let dot = DotView(color: Palette.color(for: row.state))

        let name = label(row.displayName, font: .systemFont(ofSize: 13, weight: .semibold), color: .labelColor)
        let detail = label(row.detail, font: .systemFont(ofSize: 11), color: .secondaryLabelColor)
        let time = label(row.timeText, font: .monospacedDigitSystemFont(ofSize: 11, weight: .regular),
                         color: .tertiaryLabelColor)
        time.alignment = .right
        time.setContentCompressionResistancePriority(.required, for: .horizontal)
        time.setContentHuggingPriority(.required, for: .horizontal)

        let text = NSStackView(views: [name, detail])
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 1

        for view in [dot, text, time] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            dot.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            dot.centerYAnchor.constraint(equalTo: centerYAnchor),
            dot.widthAnchor.constraint(equalToConstant: 10),
            dot.heightAnchor.constraint(equalToConstant: 10),

            text.leadingAnchor.constraint(equalTo: dot.trailingAnchor, constant: 10),
            text.centerYAnchor.constraint(equalTo: centerYAnchor),
            text.trailingAnchor.constraint(lessThanOrEqualTo: time.leadingAnchor, constant: -8),

            time.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            time.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    private func label(_ string: String, font: NSFont, color: NSColor) -> NSTextField {
        let field = NSTextField(labelWithString: string)
        field.font = font
        field.textColor = color
        field.lineBreakMode = .byTruncatingTail
        field.maximumNumberOfLines = 1
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return field
    }
}

private final class DotView: NSView {
    private let color: NSColor

    init(color: NSColor) {
        self.color = color
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func draw(_ dirtyRect: NSRect) {
        color.setFill()
        NSBezierPath(ovalIn: bounds).fill()
    }
}
