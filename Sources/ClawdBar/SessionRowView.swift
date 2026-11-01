import AppKit
import ClawdCore

/// A two-line menu row: status dot, session name and detail, an alarm bell
/// and the elapsed time. Clicking the bell arms or disarms the session's
/// alarm and keeps the menu open; clicking anywhere else brings Warp forward.
final class SessionRowView: NSView {
    static let width: CGFloat = 400
    static let height: CGFloat = 40

    /// Wide enough for the longest time text ("just now", "59m ago").
    /// Measured with the drawn width, since intrinsicContentSize under-reports
    /// it by a point or two for this font and would truncate the text.
    private static let timeColumnWidth: CGFloat = {
        let field = NSTextField(labelWithString: "")
        field.font = timeFont
        return ["just now", "59m ago", "23h 59m", "99h ago"].map { sample in
            field.stringValue = sample
            return ceil(field.fittingSize.width) + 2
        }.max() ?? 60
    }()

    private static let timeFont = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)

    private let onClick: () -> Void
    private let onToggleAlarm: () -> Bool
    private let bell = NSImageView()
    private var isHighlighted = false {
        didSet { needsDisplay = true }
    }

    /// - Parameter onToggleAlarm: Flips the session's alarm and returns whether it is now armed.
    init(row: SessionRow, isAlarmArmed: Bool, onToggleAlarm: @escaping () -> Bool, onClick: @escaping () -> Void) {
        self.onClick = onClick
        self.onToggleAlarm = onToggleAlarm
        super.init(frame: NSRect(x: 0, y: 0, width: Self.width, height: Self.height))
        build(row)
        showAlarm(armed: isAlarmArmed)
        setAccessibilityRole(.menuItem)
        setAccessibilityLabel("\(row.displayName), \(row.subtitle), \(row.timeText)")
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
        let point = convert(event.locationInWindow, from: nil)
        if bell.frame.insetBy(dx: -6, dy: -8).contains(point) {
            showAlarm(armed: onToggleAlarm())
            return
        }
        isHighlighted = false
        enclosingMenuItem?.menu?.cancelTracking()
        onClick()
    }

    private func showAlarm(armed: Bool) {
        let symbol = armed ? "bell.fill" : "bell"
        let description = armed ? "Alarm on: chime when this session needs you" : "Alarm off"
        bell.image = NSImage(systemSymbolName: symbol, accessibilityDescription: description)?
            .withSymbolConfiguration(.init(pointSize: 12, weight: .medium))
        bell.contentTintColor = armed ? Palette.waiting : .tertiaryLabelColor
        bell.toolTip = armed ? "Alarm on. Click to turn off." : "Chime when this session finishes or needs you"
        bell.setAccessibilityLabel(description)
    }

    // MARK: - Layout

    private func build(_ row: SessionRow) {
        let dot = DotView(color: Palette.color(for: row.state))

        let name = label(row.displayName, font: .systemFont(ofSize: 13, weight: .semibold), color: .labelColor)
        let detail = label(row.subtitle, font: .systemFont(ofSize: 11), color: .secondaryLabelColor)
        let time = label(row.timeText, font: Self.timeFont,
                         color: .tertiaryLabelColor)
        time.alignment = .right
        time.setContentCompressionResistancePriority(.required, for: .horizontal)
        time.setContentHuggingPriority(.required, for: .horizontal)

        bell.imageScaling = .scaleNone
        for view in [dot, name, detail, bell, time] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            dot.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            dot.centerYAnchor.constraint(equalTo: centerYAnchor),
            dot.widthAnchor.constraint(equalToConstant: 10),
            dot.heightAnchor.constraint(equalToConstant: 10),

            name.leadingAnchor.constraint(equalTo: dot.trailingAnchor, constant: 10),
            name.bottomAnchor.constraint(equalTo: centerYAnchor, constant: 1),
            name.trailingAnchor.constraint(lessThanOrEqualTo: bell.leadingAnchor, constant: -8),

            detail.leadingAnchor.constraint(equalTo: name.leadingAnchor),
            detail.topAnchor.constraint(equalTo: centerYAnchor, constant: 1),
            detail.trailingAnchor.constraint(lessThanOrEqualTo: bell.leadingAnchor, constant: -8),

            bell.trailingAnchor.constraint(equalTo: time.leadingAnchor, constant: -8),
            bell.centerYAnchor.constraint(equalTo: centerYAnchor),
            bell.widthAnchor.constraint(equalToConstant: 16),

            // A fixed column keeps the bells aligned across rows.
            time.widthAnchor.constraint(equalToConstant: Self.timeColumnWidth),
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
