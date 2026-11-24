import AppKit
import FretOSCore
import SwiftUI

/// Dev aid: `FretOS --snapshot <dir>` renders each screen to PNG (used for README screenshots).
@MainActor
enum Snapshot {
    static func run(to dir: String) {
        _ = NSApplication.shared
        Theme.registerFonts()
        let engine = Engine.shared
        engine.previewLive(LiveState(active: [.green, .yellow, .strumDown], whammyDelta: 6000, tiltDelta: 15000),
                           status: .playing, seen: [.guide])
        render(MainView().environmentObject(engine), "main", dir)
        render(MainViewAdvanced().environmentObject(engine), "advanced", dir)
        engine.previewLive(LiveState(), status: .needsPermission, seen: [])
        render(MainView().environmentObject(engine), "main-permission", dir)
        engine.previewLive(LiveState(), status: .noGuitar, seen: [])
        render(MainView().environmentObject(engine), "main-noguitar", dir)
        render(OnboardingView().environmentObject(engine), "onboarding", dir)
        engine.previewLive(LiveState(), status: .ready, seen: [])
        engine.previewUpdate("v1.2.1")
        render(MainView().environmentObject(engine), "main-update", dir)
        engine.previewUpdate(nil)
    }

    private static func render<V: View>(_ view: V, _ name: String, _ dir: String) {
        let r = ImageRenderer(content: view.environment(\.colorScheme, .dark))
        r.scale = 2
        guard let img = r.nsImage, let tiff = img.tiffRepresentation,
              let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else {
            print("failed \(name)"); return
        }
        try? png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
        print("wrote \(name).png")
    }
}

/// The Advanced sheet on its own.
struct MainViewAdvanced: View {
    var body: some View { AdvancedPanel(message: nil) {} }
}
