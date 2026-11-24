import AppKit
import FretOSCore
import SwiftUI

struct MainView: View {
    @EnvironmentObject var engine: Engine
    @State var showAdvanced = false
    @State private var message: String?
    @State private var monitor: Any?

    var body: some View {
        VStack(spacing: 12) {
            Header()
            StatusBar()
            if engine.status == .needsPermission { PermissionBanner() }
            if engine.status == .noGuitar { GuitarBanner() }
            if let tag = engine.updateAvailable { UpdateBanner(tag: tag) }
            Panel(title: "FRETS") { FretRow() }
            Panel(title: "CONTROLS") { ControlsGrid() }
            Panel(title: "TILT & WHAMMY") {
                AxisRow(input: .tilt, label: "TILT", delta: engine.live.tiltDelta,
                        threshold: engine.settings.tuning.tiltThreshold) { t in engine.setTuning { $0.tiltThreshold = t } }
                AxisRow(input: .whammy, label: "WHAMMY", delta: engine.live.whammyDelta,
                        threshold: engine.settings.tuning.whammyThreshold) { t in engine.setTuning { $0.whammyThreshold = t } }
            }
            HintLine(message: message)
            Footer(showAdvanced: $showAdvanced)
        }
        .padding(16)
        .frame(width: 500)
        .background(Theme.body)
        .preferredColorScheme(.dark)
        .onAppear(perform: installKeyCapture)
        .onDisappear { if let monitor { NSEvent.removeMonitor(monitor) }; engine.capturing = nil }
        .onChange(of: engine.capturing) { _ in message = nil }
        .sheet(isPresented: $showAdvanced) {
            AdvancedPanel(message: message) { showAdvanced = false }.environmentObject(engine)
        }
    }

    /// While a keycap is waiting, the next key pressed in this window becomes its binding.
    private func installKeyCapture() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            guard let input = engine.capturing else { return event }
            let modifiersOnly = event.type == .flagsChanged
            if modifiersOnly && event.modifierFlags.intersection([.command, .shift, .option, .control, .function]).isEmpty {
                return nil  // modifier released; ignore
            }
            switch Bindings.capture(keyCode: event.keyCode, modifiersOnly: modifiersOnly) {
            case .bind(let k): engine.bind(input, to: k)
            case .cancel: engine.capturing = nil
            case .rejected(let why):
                DispatchQueue.main.async { message = why }
            }
            return nil
        }
    }
}

// MARK: - Header & status

private struct Header: View {
    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            HStack(spacing: 3) {
                ForEach(Theme.frets, id: \.self) { f in
                    PixelRect(step: 1, steps: 1).fill(Theme.fret[f]!).frame(width: 8, height: 18)
                }
            }
            Text("FRETOS").font(Theme.pixel(20)).foregroundStyle(Theme.text)
                .shadow(color: .black, radius: 0, x: 2, y: 2)
            Spacer()
            Text("GUITAR → KEYS").font(Theme.pixel(7)).foregroundStyle(Theme.dim)
        }
        .padding(.top, 4)
    }
}

struct StatusBar: View {
    @EnvironmentObject var engine: Engine
    @State private var pulse = false

    var body: some View {
        HStack(spacing: 10) {
            PixelRect(step: 1, steps: 1).fill(ledColor).frame(width: 10, height: 10)
                .shadow(color: ledColor.opacity(0.9), radius: pulse ? 6 : 2)
                .onAppear { withAnimation(.easeInOut(duration: 0.9).repeatForever()) { pulse = true } }
            Text(engine.status.text).font(Theme.pixel(9)).foregroundStyle(Theme.text)
                .lineLimit(1).minimumScaleFactor(0.6)
            Spacer()
            if engine.status != .needsPermission && engine.status != .noGuitar {
                PixelToggle(isOn: Binding(get: { engine.enabled }, set: { engine.enabled = $0 }))
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(PixelRect(step: 2).fill(Theme.well))
        .overlay(PixelRect(step: 2).strokeBorder(Theme.panelEdge, lineWidth: 2))
    }

    private var ledColor: Color {
        switch engine.status {
        case .playing: return Theme.fret[.green]!
        case .ready, .paused: return Theme.amber
        case .noGuitar, .needsPermission: return Theme.alert
        case .off: return Theme.dim
        }
    }
}

// MARK: - Banners

/// Walks the user through the keystroke permission, one step at a time.
private struct PermissionBanner: View {
    @EnvironmentObject var engine: Engine
    var body: some View {
        Banner(step: engine.askedForPermission ? "STEP 2 OF 2" : "STEP 1 OF 2") {
            if !engine.askedForPermission {
                Text("FretOS needs your OK to press keys in Clone Hero.")
                    .font(Theme.body(13)).foregroundStyle(Theme.text)
                Text("Click ALLOW, then switch FretOS ON in the list that opens.")
                    .font(Theme.body(11)).foregroundStyle(Theme.dim)
            } else {
                Text("Switched FretOS on? Reopen FretOS to finish.")
                    .font(Theme.body(13)).foregroundStyle(Theme.text)
                Text("Already ON but still stuck? Select FretOS in the list, click –, then ALLOW again.")
                    .font(Theme.body(11)).foregroundStyle(Theme.dim)
            }
        } action: {
            if engine.askedForPermission {
                PixelButton(title: "REOPEN", tint: Theme.amber) { Permission.relaunch() }
                PixelButton(title: "ALLOW") { engine.askForPermission() }
            } else {
                PixelButton(title: "ALLOW", tint: Theme.amber) { engine.askForPermission() }
            }
        }
    }
}

private struct GuitarBanner: View {
    var body: some View {
        Banner(step: nil) {
            Text("Plug your wired Xbox 360 guitar into a USB port.")
                .font(Theme.body(13)).foregroundStyle(Theme.text)
            Text("Already plugged in? Unplug it, wait a second, plug it back in. Quit any other app using it.")
                .font(Theme.body(11)).foregroundStyle(Theme.dim)
        } action: { EmptyView() }
    }
}

private struct UpdateBanner: View {
    let tag: String
    @EnvironmentObject var engine: Engine
    var body: some View {
        Banner(step: "UPDATE AVAILABLE") {
            Text("FretOS \(tag.hasPrefix("v") ? String(tag.dropFirst()) : tag) is out.")
                .font(Theme.body(13)).foregroundStyle(Theme.text)
            Text("Download it, unzip it, and drag the new FretOS into Applications (replace the old one).")
                .font(Theme.body(11)).foregroundStyle(Theme.dim)
        } action: {
            PixelButton(title: "DOWNLOAD", tint: Theme.amber) { engine.downloadUpdate() }
            PixelButton(title: "SKIP") { engine.skipUpdate() }
        }
    }
}

private struct Banner<Content: View, Action: View>: View {
    let step: String?
    @ViewBuilder var content: Content
    @ViewBuilder var action: Action
    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                if let step { Text(step).font(Theme.pixel(7)).foregroundStyle(Theme.amber) }
                content
            }
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            VStack(spacing: 6) { action }
        }
        .padding(14)
        .background(PixelRect(step: 2).fill(Theme.amber.opacity(0.08)))
        .overlay(PixelRect(step: 2).strokeBorder(Theme.amber.opacity(0.7), lineWidth: 2))
    }
}

// MARK: - Frets

private struct FretRow: View {
    @EnvironmentObject var engine: Engine
    var body: some View {
        HStack(spacing: 0) {
            ForEach(Theme.frets, id: \.self) { f in
                VStack(spacing: 10) {
                    FretButton(color: Theme.fret[f]!, lit: engine.live.active.contains(f))
                    Keycap(input: f)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
}

private struct FretButton: View {
    let color: Color
    let lit: Bool
    var body: some View {
        ZStack {
            PixelRect(step: 3).fill(color.opacity(lit ? 1 : 0.22))
            PixelRect(step: 3).strokeBorder(lit ? color : color.opacity(0.5), lineWidth: 2)
            // glossy top band, like the real buttons
            Rectangle().fill(.white.opacity(lit ? 0.35 : 0.08)).frame(height: 6).padding(.horizontal, 10)
                .frame(maxHeight: .infinity, alignment: .top).padding(.top, 8)
        }
        .frame(width: 58, height: 58)
        .shadow(color: lit ? color.opacity(0.8) : .clear, radius: 12)
        .scaleEffect(lit ? 0.96 : 1)
        .animation(.easeOut(duration: 0.06), value: lit)
    }
}

// MARK: - Controls

private struct ControlsGrid: View {
    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
            GridRow {
                ControlCell(input: .strumUp, label: "STRUM ▲")
                ControlCell(input: .start, label: "START")
            }
            GridRow {
                ControlCell(input: .strumDown, label: "STRUM ▼")
                ControlCell(input: .back, label: "STAR PWR")
            }
        }
    }
}

private struct ControlCell: View {
    let input: GuitarInput
    let label: String
    @EnvironmentObject var engine: Engine
    var body: some View {
        HStack(spacing: 10) {
            Text(label).font(Theme.pixel(8))
                .foregroundStyle(engine.live.active.contains(input) ? Theme.amber : Theme.text)
                .frame(width: 92, alignment: .leading)
            Keycap(input: input, width: 60)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Tilt & whammy

private struct AxisRow: View {
    let input: GuitarInput
    let label: String
    let delta: Int
    let threshold: Int
    let setThreshold: (Int) -> Void
    @EnvironmentObject var engine: Engine

    // Slider left = least sensitive (31000), right = most (4000) (more sensitive = triggers with less movement).
    private static let range = (lo: 4000.0, hi: 31000.0)

    var body: some View {
        HStack(spacing: 12) {
            Text(label).font(Theme.pixel(8))
                .foregroundStyle(engine.live.active.contains(input) ? Theme.amber : Theme.text)
                .frame(width: 62, alignment: .leading)
            VStack(alignment: .leading, spacing: 6) {
                AxisMeter(value: Double(delta) / 32768, trigger: Double(threshold) / 32768,
                          lit: engine.live.active.contains(input))
                HStack(spacing: 6) {
                    Text("SENS").font(Theme.pixel(6)).foregroundStyle(Theme.dim)
                    Slider(value: Binding(
                        get: { (Self.range.hi - Double(threshold)) / (Self.range.hi - Self.range.lo) },
                        set: { setThreshold(Int(Self.range.hi - $0 * (Self.range.hi - Self.range.lo))) }
                    ))
                    .controlSize(.mini).tint(Theme.amber)
                    .accessibilityLabel("\(label) sensitivity")
                }
            }
            Keycap(input: input)
        }
    }
}

/// Segmented LED meter: how far the guitar has moved, with a marker where it triggers.
private struct AxisMeter: View {
    let value: Double     // 0…1
    let trigger: Double   // 0…1
    let lit: Bool
    private let segments = 24

    var body: some View {
        GeometryReader { geo in
            let w = (geo.size.width - CGFloat(segments - 1) * 2) / CGFloat(segments)
            ZStack(alignment: .topLeading) {
                HStack(spacing: 2) {
                    ForEach(0..<segments, id: \.self) { i in
                        let on = Double(i) / Double(segments) < min(value, 1)
                        Rectangle().fill(on ? (lit ? Theme.amber : Theme.chromeBottom) : Theme.well)
                            .frame(width: w)
                    }
                }
                Rectangle().fill(Theme.text).frame(width: 2, height: geo.size.height + 6)
                    .offset(x: CGFloat(trigger) * geo.size.width - 1, y: -3)
            }
        }
        .frame(height: 12)
        .accessibilityHidden(true)
    }
}

// MARK: - Footer, hints, advanced

private struct HintLine: View {
    let message: String?
    @EnvironmentObject var engine: Engine
    var body: some View {
        let text = message ?? defaultHint
        if let text {
            Text(text).font(Theme.body(11)).foregroundStyle(message != nil ? Theme.alert : Theme.dim)
                .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 2)
        }
    }
    private var defaultHint: String? {
        if engine.capturing != nil { return "Press the key you want · Esc to cancel" }
        let dupes = Bindings.duplicates(engine.settings.bindings)
        guard let (key, inputs) = dupes.first else { return nil }
        let names = inputs.map(\.displayName).joined(separator: " and ")
        return "\(names) both press \(KeyNames.label(key))."
    }
}

private struct Footer: View {
    @Binding var showAdvanced: Bool
    @EnvironmentObject var engine: Engine
    var body: some View {
        HStack(spacing: 10) {
            Text("PRESET").font(Theme.pixel(7)).foregroundStyle(Theme.dim)
            Text(engine.settings.presetName.uppercased()).font(Theme.pixel(8)).foregroundStyle(Theme.text)
            if engine.settings.presetName != Preset.cloneHeroDefault.name {
                PixelButton(title: "RESET") { engine.resetToDefaults() }
            }
            Spacer()
            PixelButton(title: "ADVANCED") { showAdvanced = true }
        }
    }
}

struct AdvancedPanel: View {
    var message: String?
    var done: () -> Void
    @EnvironmentObject var engine: Engine

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("ADVANCED").font(Theme.pixel(12)).foregroundStyle(Theme.text)
                Spacer()
                PixelButton(title: "DONE", tint: Theme.amber, action: done).keyboardShortcut(.defaultAction)
            }
            Panel(title: "TUNING") {
                Row("Strum debounce", "Raise it if you get double strums.") {
                    PixelButton(title: "–") { engine.setTuning { $0.strumDebounceMs = max(10, $0.strumDebounceMs - 5) } }
                    Text("\(engine.settings.tuning.strumDebounceMs) MS").font(Theme.pixel(8)).foregroundStyle(Theme.text).frame(width: 60)
                    PixelButton(title: "+") { engine.setTuning { $0.strumDebounceMs = min(50, $0.strumDebounceMs + 5) } }
                }
                Row("Recalibrate tilt & whammy", "Hold the guitar level, hands off the whammy.") {
                    PixelButton(title: "RECALIBRATE") { engine.recalibrate() }
                }
                Row("Whammy depth (experimental)", "Taps the whammy key faster the further you push. Off = simple on/off.") {
                    PixelToggle(isOn: Binding(get: { engine.settings.tuning.whammyPulse },
                                              set: { v in engine.setTuning { $0.whammyPulse = v } }))
                }
                Row("Only send keys to Clone Hero", "Stops a stray strum typing into other apps.") {
                    PixelToggle(isOn: $engine.settings.onlyWhenCloneHeroFront)
                }
                Row("Open FretOS when I log in", nil) {
                    PixelToggle(isOn: $engine.settings.launchAtLogin)
                }
                Row("Tell me when there's an update", "Checks GitHub once a day. Nothing about you is sent.") {
                    PixelToggle(isOn: $engine.settings.checkForUpdates)
                }
                Row("Report a problem", "Opens a GitHub form with your FretOS, macOS and guitar info filled in. Nothing is sent until you submit it.") {
                    PixelButton(title: "REPORT") { engine.reportProblem() }
                }
            }
            Panel(title: "EXTRA BUTTONS") {
                Text("Dimmed ones haven't been pressed yet — not every guitar has them.")
                    .font(Theme.body(11)).foregroundStyle(Theme.dim)
                Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 8) {
                    ForEach(0..<3, id: \.self) { row in
                        GridRow {
                            ForEach(0..<2, id: \.self) { col in
                                ExtraCell(input: GuitarInput.extras[row * 2 + col])
                            }
                        }
                    }
                }
            }
            if let message {
                Text(message).font(Theme.body(11)).foregroundStyle(Theme.alert)
            }
        }
        .padding(16)
        .frame(width: 500)
        .background(Theme.body)
        .preferredColorScheme(.dark)
    }
}

private struct Row<Trailing: View>: View {
    let title: String
    let detail: String?
    @ViewBuilder var trailing: Trailing
    init(_ title: String, _ detail: String?, @ViewBuilder trailing: () -> Trailing) {
        self.title = title; self.detail = detail; self.trailing = trailing()
    }
    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Theme.body(13)).foregroundStyle(Theme.text)
                if let detail { Text(detail).font(Theme.body(11)).foregroundStyle(Theme.dim) }
            }
            Spacer(minLength: 8)
            trailing
        }
    }
}

private struct ExtraCell: View {
    let input: GuitarInput
    @EnvironmentObject var engine: Engine
    var body: some View {
        let seen = engine.seen.contains(input)
        HStack {
            Text(input.displayName.uppercased()).font(Theme.pixel(7))
                .foregroundStyle(engine.live.active.contains(input) ? Theme.amber : (seen ? Theme.text : Theme.dim))
            Spacer(minLength: 6)
            Keycap(input: input, width: 48).opacity(seen ? 1 : 0.55)
        }
        .frame(maxWidth: .infinity)
    }
}
