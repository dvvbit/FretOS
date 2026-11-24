import FretOSCore
import SwiftUI

/// Three screens, each moves on by itself the moment its step is done.
struct OnboardingView: View {
    @EnvironmentObject var engine: Engine
    @State private var step = 0
    @State private var askedForPermission = false
    @State private var showReopen = false

    var body: some View {
        VStack(spacing: 22) {
            HStack(spacing: 3) {
                ForEach(0..<3, id: \.self) { i in
                    Rectangle().fill(i <= step ? Theme.amber : Theme.panelEdge).frame(width: 28, height: 4)
                }
            }
            .padding(.top, 8)

            Spacer(minLength: 0)
            Group {
                switch step {
                case 0: plugIn
                case 1: permission
                default: pressGreen
                }
            }
            .frame(maxWidth: .infinity)
            .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))
            Spacer(minLength: 0)

            Button("Skip setup") { finish() }
                .buttonStyle(.plain).font(Theme.body(11)).foregroundStyle(Theme.dim)
        }
        .padding(28)
        .frame(width: 500, height: 500)
        .background(Theme.body)
        .preferredColorScheme(.dark)
        .onAppear(perform: advanceIfDone)
        .onChange(of: engine.status) { _ in advanceIfDone() }
        .onChange(of: engine.permissionGranted) { _ in advanceIfDone() }
        .onChange(of: engine.live) { _ in advanceIfDone() }
    }

    // MARK: steps

    private var plugIn: some View {
        VStack(spacing: 18) {
            LogoImage().frame(width: 140, height: 140).modifier(Bob())
            PluggingGuitar().scaleEffect(0.6).frame(height: 30)
            Title("PLUG IN YOUR GUITAR")
            Explain("Connect your wired Xbox 360 guitar to a USB port. FretOS finds it automatically.")
        }
    }

    private var permission: some View {
        VStack(spacing: 18) {
            KeyGlyph()
            Title("LET FRETOS PRESS KEYS")
            Explain("macOS needs your OK before an app can send keystrokes. Click below, then switch FretOS on in the list.")
            PixelButton(title: "OPEN SETTINGS", tint: Theme.amber) {
                engine.askForPermission()
                askedForPermission = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 8) { showReopen = true }
            }
            if showReopen && askedForPermission {
                VStack(spacing: 8) {
                    Explain("Already switched it on? Reopen FretOS so macOS applies it.")
                    PixelButton(title: "REOPEN FRETOS") { Permission.relaunch() }
                }
            }
        }
    }

    private var pressGreen: some View {
        VStack(spacing: 18) {
            PixelRect(step: 3).fill(Theme.fret[.green]!).frame(width: 72, height: 72)
                .shadow(color: Theme.fret[.green]!.opacity(0.7), radius: 14)
                .modifier(Bob())
            Title("PRESS THE GREEN FRET")
            Explain("Just to make sure everything's talking.")
        }
    }

    // MARK: flow

    private func advanceIfDone() {
        var next = step
        if next == 0 && engine.status != .noGuitar { next = 1 }
        if next == 1 && engine.permissionGranted { next = 2 }
        if next == 2 && engine.live.active.contains(.green) { finish(); return }
        if next != step { withAnimation(.easeOut(duration: 0.25)) { step = next } }
    }

    private func finish() {
        withAnimation { engine.settings.onboarded = true }
    }
}

private struct Title: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(Theme.pixel(13)).foregroundStyle(Theme.text).multilineTextAlignment(.center)
    }
}

private struct Explain: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(Theme.body(13)).foregroundStyle(Theme.dim)
            .multilineTextAlignment(.center).frame(maxWidth: 340).fixedSize(horizontal: false, vertical: true)
    }
}

/// A pixel USB plug sliding into a port, on loop.
private struct PluggingGuitar: View {
    @State private var inserted = false
    var body: some View {
        HStack(spacing: 0) {
            Rectangle().fill(Theme.chromeBottom).frame(width: 60, height: 6)          // cable
            PixelRect(step: 2, steps: 1).fill(Theme.chromeTop).frame(width: 34, height: 22) // plug
            Rectangle().fill(Theme.chromeBottom).frame(width: 14, height: 12)         // tip
        }
        .offset(x: inserted ? 18 : -10)
        .overlay(alignment: .trailing) {
            PixelRect(step: 2, steps: 1).strokeBorder(Theme.amber, lineWidth: 3).frame(width: 26, height: 22)
                .offset(x: 34)
        }
        .frame(height: 72)
        .onAppear { withAnimation(.easeInOut(duration: 0.9).repeatForever()) { inserted = true } }
    }
}

/// The FretOS mark: five fret blocks, big.
private struct FretMark: View {
    var body: some View {
        HStack(spacing: 8) {
            ForEach(Array(Theme.frets.enumerated()), id: \.offset) { i, f in
                PixelRect(step: 3, steps: 1).fill(Theme.fret[f]!)
                    .frame(width: 22, height: [54, 72, 90, 72, 54][i])
                    .shadow(color: Theme.fret[f]!.opacity(0.6), radius: 10)
            }
        }
        .frame(height: 110)
    }
}

private struct KeyGlyph: View {
    var body: some View {
        Text("A").font(Theme.pixel(22)).foregroundStyle(Theme.ink)
            .frame(width: 72, height: 72)
            .background(PixelRect(step: 3).fill(LinearGradient(colors: [Theme.chromeTop, Theme.chromeBottom],
                                                               startPoint: .top, endPoint: .bottom)))
            .overlay(PixelRect(step: 3).strokeBorder(Theme.chromeEdge, lineWidth: 3))
            .modifier(Bob())
    }
}

private struct Bob: ViewModifier {
    @State private var up = false
    func body(content: Content) -> some View {
        content.offset(y: up ? -4 : 0)
            .onAppear { withAnimation(.easeInOut(duration: 0.7).repeatForever()) { up = true } }
    }
}
