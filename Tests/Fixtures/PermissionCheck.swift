// Manual integration fixture only; never embedded in the production app.
import AppKit
import Network

@MainActor
final class PermissionCheckDelegate: NSObject, NSApplicationDelegate {
    private var browser: NWBrowser?
    private var states: [String] = []
    func applicationDidFinishLaunching(_ notification: Notification) {
        let destination = Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("permission-check-result.json")
        save(destination, finished: false)
        let browser = NWBrowser(for: .bonjour(type: "_maca-permcheck._tcp", domain: nil), using: .tcp)
        self.browser = browser
        browser.stateUpdateHandler = { [weak self] state in
            let label: String
            switch state {
            case .setup: label = "setup"
            case .ready: label = "ready"
            case .waiting: label = "waiting"
            case .failed: label = "failed"
            case .cancelled: label = "cancelled"
            @unknown default: label = "unknown"
            }
            Task { @MainActor in self?.states.append(label); self?.save(destination, finished: false) }
        }
        browser.start(queue: .main)
        DispatchQueue.main.asyncAfter(deadline: .now() + 45) { [weak self] in
            self?.save(destination, finished: true)
            self?.browser?.cancel()
            NSApplication.shared.terminate(nil)
        }
    }
    private func save(_ destination: URL, finished: Bool) {
        let result: [String: Any] = ["probe": "localNetwork", "states": states, "finished": finished,
                                    "at": ISO8601DateFormatter().string(from: Date())]
        if let data = try? JSONSerialization.data(withJSONObject: result, options: [.sortedKeys]) {
            try? data.write(to: destination, options: .atomic)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)
        }
    }
}

@main
struct PermissionCheckMain {
    @MainActor static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let delegate = PermissionCheckDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
