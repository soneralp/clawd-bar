import AppKit
import ClawdCore

/// Owns the status item: watches the session directory, renders the icon and
/// title, rebuilds the dropdown menu and rings per-session alarms.
final class StatusController: NSObject, NSMenuDelegate {
    /// How often dead sessions are pruned and elapsed times refreshed.
    static let refreshInterval: TimeInterval = 15
    /// Duration of one frame of the working animation.
    static let animationFrameInterval: TimeInterval = 0.2

    private let store: SessionStore
    private let chime = Chime()
    private var alarms = Alarms(armed: Settings.armedAlarms)
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()
    private lazy var watcher = DirectoryWatcher(url: store.directory) { [weak self] in self?.refresh() }
    private var refreshTimer: Timer?
    private var animationTimer: Timer?
    private var animationFrame = 0
    private var aggregate = Aggregate(records: [], now: 0)
    /// Reading settings.json on every refresh would be wasteful; it only
    /// changes when the user toggles it or edits the file by hand.
    private var hooksInstalled = false
    private var isMenuOpen = false

    init(store: SessionStore) {
        self.store = store
        super.init()
    }

    func start() {
        do {
            try store.ensureDirectory()
        } catch {
            NSLog("Clawd Bar: cannot create \(store.directory.path): \(error)")
        }
        menu.delegate = self
        menu.autoenablesItems = false
        statusItem.menu = menu
        statusItem.button?.imagePosition = .imageLeading

        hooksInstalled = HooksInstaller.isInstalled()
        watcher.start()
        refreshTimer = scheduledTimer(interval: Self.refreshInterval) { [weak self] in self?.refresh() }
        refresh()
    }

    /// Reloads all records, drops sessions whose process is gone and updates the UI.
    func refresh() {
        let records = store.prune(isAlive: ProcessTree.isAlive)
        let next = Aggregate(records: records, now: Date().timeIntervalSince1970)
        ringAlarms(from: aggregate, to: next)
        aggregate = next
        render()
    }

    // MARK: - NSMenuDelegate

    func menuNeedsUpdate(_ menu: NSMenu) {
        hooksInstalled = HooksInstaller.isInstalled()
        refresh()
    }

    func menuWillOpen(_ menu: NSMenu) {
        isMenuOpen = true
    }

    func menuDidClose(_ menu: NSMenu) {
        isMenuOpen = false
    }

    // MARK: - Rendering

    private func render() {
        guard let button = statusItem.button else { return }
        button.title = aggregate.title.isEmpty ? "" : " \(aggregate.title)"
        button.toolTip = tooltip()
        updateAnimation()
        // Rebuilding while the menu is tracking would destroy the row under the cursor.
        if !isMenuOpen { rebuildMenu() }
    }

    private func tooltip() -> String {
        switch aggregate.icon {
        case .idle: "No Claude Code sessions"
        case .waiting: "Waiting for you: \(aggregate.title)"
        case .running: "Claude is working"
        case .done: "All sessions finished"
        }
    }

    /// Clawd hops while any session is working, in the color of the most
    /// urgent state; otherwise it stands still.
    private func updateAnimation() {
        guard aggregate.isAnyRunning else {
            animationTimer?.invalidate()
            animationTimer = nil
            statusItem.button?.image = PixelIcon.image(for: aggregate.icon)
            return
        }
        showAnimationFrame()
        guard animationTimer == nil else { return }
        animationTimer = scheduledTimer(interval: Self.animationFrameInterval) { [weak self] in
            guard let self else { return }
            self.animationFrame = (self.animationFrame + 1) % PixelIcon.workingFrameCount
            self.showAnimationFrame()
        }
    }

    private func showAnimationFrame() {
        statusItem.button?.image = PixelIcon.workingImage(for: aggregate.icon, frame: animationFrame)
    }

    private func rebuildMenu() {
        menu.removeAllItems()

        if aggregate.active.isEmpty && aggregate.finished.isEmpty {
            menu.addItem(disabledItem("No active sessions"))
        } else {
            aggregate.active.forEach { menu.addItem(rowItem($0)) }
            if !aggregate.active.isEmpty && !aggregate.finished.isEmpty {
                menu.addItem(.separator())
            }
            aggregate.finished.forEach { menu.addItem(rowItem($0)) }
        }

        menu.addItem(.separator())
        menu.addItem(toggleItem("Launch at Login", isOn: Settings.launchAtLogin, action: #selector(toggleLaunchAtLogin)))

        menu.addItem(.separator())
        let hooksItem = actionItem(
            hooksInstalled ? "Remove Claude Code Hooks" : "Install Claude Code Hooks…",
            action: #selector(toggleHooks)
        )
        if !hooksInstalled {
            hooksItem.image = NSImage(systemSymbolName: "exclamationmark.triangle.fill",
                                      accessibilityDescription: "Hooks not installed")
        }
        menu.addItem(hooksItem)

        menu.addItem(.separator())
        menu.addItem(actionItem("Quit Clawd Bar", action: #selector(quit), keyEquivalent: "q"))
    }

    private func rowItem(_ row: SessionRow) -> NSMenuItem {
        let item = NSMenuItem()
        item.view = SessionRowView(
            row: row,
            isAlarmArmed: alarms.isArmed(row.sessionId),
            onToggleAlarm: { [weak self] in self?.toggleAlarm(row.sessionId) ?? false },
            onClick: WarpLauncher.activate
        )
        return item
    }

    private func disabledItem(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func actionItem(_ title: String, action: Selector, keyEquivalent: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.target = self
        return item
    }

    private func toggleItem(_ title: String, isOn: Bool, action: Selector) -> NSMenuItem {
        let item = actionItem(title, action: action)
        item.state = isOn ? .on : .off
        return item
    }

    // MARK: - Alarms

    /// Chimes once per refresh if any armed session just finished or started
    /// waiting, and forgets alarms of sessions that ended.
    private func ringAlarms(from previous: Aggregate, to next: Aggregate) {
        if !alarms.sessionsToRing(from: previous, to: next).isEmpty {
            chime.play()
        }
        // An empty snapshot may be a transient read failure; keep alarms until sessions are really gone.
        guard !(next.active.isEmpty && next.finished.isEmpty) else { return }
        let before = alarms
        alarms.retainOnly(next)
        if alarms != before { Settings.armedAlarms = alarms.armed }
    }

    private func toggleAlarm(_ sessionId: String) -> Bool {
        alarms.toggle(sessionId)
        Settings.armedAlarms = alarms.armed
        return alarms.isArmed(sessionId)
    }

    // MARK: - Actions

    @objc private func toggleLaunchAtLogin() {
        do {
            try Settings.setLaunchAtLogin(!Settings.launchAtLogin)
        } catch {
            showError("Could not change the login item.", error)
        }
        rebuildMenu()
    }

    @objc private func toggleHooks() {
        do {
            if HooksInstaller.isInstalled() {
                try HooksInstaller.remove()
            } else {
                try HooksInstaller.install()
            }
        } catch {
            showError("Could not update ~/.claude/settings.json.", error)
        }
        hooksInstalled = HooksInstaller.isInstalled()
        if hooksInstalled { showRestartHint() }
        rebuildMenu()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func showRestartHint() {
        let alert = NSAlert()
        alert.messageText = "Hooks installed"
        alert.informativeText = "Claude Code reads hooks when a session starts. Restart running sessions to see them in the menu bar."
        NSApp.activate()
        alert.runModal()
    }

    private func showError(_ message: String, _ error: Error) {
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        NSApp.activate()
        alert.runModal()
    }

    /// A repeating timer that also fires while the menu is open.
    private func scheduledTimer(interval: TimeInterval, _ block: @escaping () -> Void) -> Timer {
        let timer = Timer(timeInterval: interval, repeats: true) { _ in block() }
        RunLoop.main.add(timer, forMode: .common)
        return timer
    }
}
