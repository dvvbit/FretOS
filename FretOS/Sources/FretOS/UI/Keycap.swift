import FretOSCore
import SwiftUI

/// A chrome keycap showing the key an input sends. Click to rebind, right-click to clear.
struct Keycap: View {
    let input: GuitarInput
    @EnvironmentObject var engine: Engine
    var width: CGFloat = 52

    private var key: UInt16? { engine.settings.bindings[input] }
    private var isCapturing: Bool { engine.capturing == input }
    private var isLit: Bool { engine.live.active.contains(input) }

    var body: some View {
        Button {
            engine.capturing = isCapturing ? nil : input
        } label: {
            ZStack {
                if isCapturing {
                    BlinkingText(text: "KEY?")
                } else {
                    Text(key.map(KeyNames.label) ?? "—")
                        .font(Theme.pixel(labelSize))
                        .foregroundStyle(key == nil ? Theme.dim : Theme.ink)
                        .lineLimit(1).minimumScaleFactor(0.5)
                }
            }
            .frame(width: width, height: 34)
            .background(
                PixelRect(step: 2, steps: 1).fill(isCapturing
                    ? AnyShapeStyle(Theme.amber)
                    : AnyShapeStyle(LinearGradient(colors: [Theme.chromeTop, Theme.chromeBottom],
                                                   startPoint: .top, endPoint: .bottom)))
                    // shadow on the cap only, never on the label
                    .shadow(color: isLit ? Theme.amber.opacity(0.6) : .black.opacity(0.6),
                            radius: isLit ? 6 : 0, y: isLit ? 0 : 2)
            )
            .overlay(alignment: .top) {   // top highlight line
                Rectangle().fill(.white.opacity(isCapturing ? 0 : 0.7)).frame(height: 1).padding(.horizontal, 6).padding(.top, 3)
            }
            .overlay(PixelRect(step: 2, steps: 1).strokeBorder(isLit ? Theme.amber : Theme.chromeEdge, lineWidth: 2))
        }
        .buttonStyle(PressableStyle())
        .help(isCapturing ? "Press any key (Esc to cancel)" : "Click to change · right-click to clear")
        .contextMenu {
            Button("Clear") { engine.bind(input, to: nil) }
            if let d = Preset.cloneHeroDefault.bindings[input] {
                Button("Reset to \(KeyNames.label(d))") { engine.bind(input, to: d) }
            }
        }
        .accessibilityLabel("\(input.displayName) key: \(key.map(KeyNames.label) ?? "none")")
    }

    private var labelSize: CGFloat {
        let n = (key.map(KeyNames.label) ?? "—").count
        return n <= 2 ? 12 : n <= 4 ? 8 : 6
    }
}

struct BlinkingText: View {
    let text: String
    @State private var on = true
    var body: some View {
        Text(text).font(Theme.pixel(8)).foregroundStyle(Theme.ink)
            .opacity(on ? 1 : 0.15)
            .onAppear { withAnimation(.easeInOut(duration: 0.45).repeatForever()) { on = false } }
    }
}

extension GuitarInput {
    var displayName: String {
        switch self {
        case .green: return "Green"
        case .red: return "Red"
        case .yellow: return "Yellow"
        case .blue: return "Blue"
        case .orange: return "Orange"
        case .strumUp: return "Strum up"
        case .strumDown: return "Strum down"
        case .start: return "Start"
        case .back: return "Star Power"
        case .tilt: return "Tilt"
        case .whammy: return "Whammy"
        case .guide: return "Guide"
        case .dpadLeft: return "D-pad ←"
        case .dpadRight: return "D-pad →"
        case .rb: return "RB"
        case .leftStickClick: return "L-stick click"
        case .rightStickClick: return "R-stick click"
        }
    }
}
