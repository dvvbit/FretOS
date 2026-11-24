import ServiceManagement

enum LaunchAtLogin {
    static func set(_ on: Bool) {
        do { on ? try SMAppService.mainApp.register() : try SMAppService.mainApp.unregister() }
        catch { NSLog("FretOS: launch at login \(on) failed: \(error)") }
    }
}
