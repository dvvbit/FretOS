import AppKit
import CoreGraphics

/// macOS "Accessibility" permission, needed to send keystrokes.
enum Permission {
    static var granted: Bool { CGPreflightPostEventAccess() }
    static func request() { _ = CGRequestPostEventAccess() }
    static func openSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }
    /// Relaunch so a freshly granted permission takes effect.
    static func relaunch() {
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: config) { _, _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }
}
