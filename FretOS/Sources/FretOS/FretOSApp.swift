import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    // Keep running in the menu bar when the window is closed.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

struct FretOSApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var engine = Engine.shared

    init() {
        Theme.registerFonts()
        MainActor.assumeIsolated { Engine.shared.start() }
    }

    var body: some Scene {
        Window("FretOS", id: "main") {
            RootView().environmentObject(engine)
        }
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)

        MenuBarExtra {
            MenuBarMenu().environmentObject(engine)
        } label: {
            Image(systemName: engine.status == .playing ? "guitars.fill" : "guitars")
        }
    }
}

/// First run shows setup; afterwards the main screen.
struct RootView: View {
    @EnvironmentObject var engine: Engine
    var body: some View {
        if engine.settings.onboarded { MainView() } else { OnboardingView() }
    }
}
