import AppKit
import ClawdCore

/// Owns the status item: watches the session directory, renders the icon and
/// title, rebuilds the dropdown menu and fires optional alerts.
final class StatusController: NSObject, NSMenuDelegate {
    /// How often dead sessions are pruned and elapsed times refreshed.
    static let refreshInterval: TimeInterval = 15
    /// Half-period of the "running" pulse.
    static let pulseInterval: TimeInterval = 0.6
    static let pulseDimAlpha: CGFloat = 0.35

    private let store: SessionStore
    private let notifier = Notifier()
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()
    private lazy var watcher = DirectoryWatcher(url: store.directory) { [weak self] in self?.refresh() }
    private var refreshTimer: Timer?
    private var pulseTimer: Timer?
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
        announceTransitions(from: aggregate, to: next)
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
        button.image = PixelIcon.image(for: aggregate.icon)
        button.title = aggregate.title.isEmpty ? "" : " \(aggregate.title)"
        button.toolTip = tooltip()
        updatePulse()
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

    private func updatePulse() {
        guard aggregate.icon == .running else {
            pulseTimer?.invalidate()
            pulseTimer = nil
            statusItem.button?.alphaValue = 1
            return
        }
        guard pulseTimer == nil else { return }
        pulseTimer = scheduledTimer(interval: Self.pulseInterval) { [weak self] in
            guard let button = self?.statusItem.button else { return }
            button.alphaValue = button.alphaValue < 1 ? 1 : Self.pulseDimAlpha
        }
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
        menu.addItem(toggleItem("Notify When Waiting or Done", isOn: Settings.notificationsEnabled,
                                action: #selector(toggleNotifications)))
        menu.addItem(toggleItem("Play Sound", isOn: Settings.soundEnabled, action: #selector(toggleSound)))
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
        item.view = SessionRowView(row: row, onClick: WarpLauncher.activate)
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

    // MARK: - Alerts

    /// Alerts on running → waiting and running → done, never on the first load.
    private func announceTransitions(from previous: Aggregate, to next: Aggregate) {
        let previousStates = Dictionary(
            (previous.active + previous.finished).map { ($0.sessionId, $0.state) },
            uniquingKeysWith: { first, _ in first }
        )
        for row in next.active + next.finished where previousStates[row.sessionId] == .running && row.state != .running {
            notifier.notify(row)
        }
    }

    // MARK: - Actions

    @objc private func toggleNotifications() {
        Settings.notificationsEnabled.toggle()
        if Settings.notificationsEnabled { notifier.requestAuthorization() }
        rebuildMenu()
    }

    @objc private func toggleSound() {
        Settings.soundEnabled.toggle()
        rebuildMenu()
    }

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
