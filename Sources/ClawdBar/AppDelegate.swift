import AppKit
import ClawdCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusController: StatusController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let controller = StatusController(store: SessionStore(directory: SessionStore.defaultDirectory))
        controller.start()
        statusController = controller
    }
}
