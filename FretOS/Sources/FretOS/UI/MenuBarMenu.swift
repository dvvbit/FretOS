import SwiftUI

struct MenuBarMenu: View {
    @EnvironmentObject var engine: Engine
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Text(engine.status.text)
        Toggle("FretOS On", isOn: Binding(get: { engine.enabled }, set: { engine.enabled = $0 }))
        Divider()
        Button("Open FretOS…") {
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }
        Button("Quit FretOS") { NSApp.terminate(nil) }.keyboardShortcut("q")
    }
}
