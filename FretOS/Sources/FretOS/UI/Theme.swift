import AppKit
import CoreText
import FretOSCore
import SwiftUI

enum Theme {
    // Body & panels: near-black, like the guitar's body.
    static let body = Color(hex: 0x0D0D0F)
    static let panel = Color(hex: 0x16161A)
    static let panelEdge = Color(hex: 0x2A2A31)
    static let well = Color(hex: 0x08080A)
    // Chrome keycaps.
    static let chromeTop = Color(hex: 0xEDEFF2)
    static let chromeBottom = Color(hex: 0x9499A2)
    static let chromeEdge = Color(hex: 0x050506)
    static let ink = Color(hex: 0x141416)
    // Text.
    static let text = Color(hex: 0xE9E9EC)
    static let dim = Color(hex: 0x70737C)
    // The one non-fret accent: an amber status LED.
    static let amber = Color(hex: 0xFFB020)
    static let alert = Color(hex: 0xF0413C)

    static let fret: [GuitarInput: Color] = [
        .green: Color(hex: 0x35D46C), .red: Color(hex: 0xF0413C), .yellow: Color(hex: 0xF7D23B),
        .blue: Color(hex: 0x3D8BFF), .orange: Color(hex: 0xFF8A1F),
    ]
    static let frets: [GuitarInput] = [.green, .red, .yellow, .blue, .orange]

    static let pixelFontName = "PressStart2P-Regular"

    /// The pixel font. Only for headings, labels and keycaps.
    static func pixel(_ size: CGFloat) -> Font { .custom(pixelFontName, fixedSize: size) }

    /// Plain system font for explanatory sentences.
    static func body(_ size: CGFloat = 12) -> Font { .system(size: size) }

    static func registerFonts() {
        guard let url = Resources.url("PressStart2P-Regular.ttf") else {
            NSLog("FretOS: pixel font missing"); return
        }
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255, opacity: 1)
    }
}

/// Finds bundled files both in the packaged .app (Contents/Resources) and in `swift run` builds.
enum Resources {
    static func url(_ name: String) -> URL? {
        if let u = Bundle.main.resourceURL?.appendingPathComponent(name), FileManager.default.fileExists(atPath: u.path) {
            return u
        }
        let exeDir = Bundle.main.executableURL!.deletingLastPathComponent()
        for sub in ["FretOS_FretOS.bundle/Resources", "FretOS_FretOS.bundle/Contents/Resources/Resources"] {
            let u = exeDir.appendingPathComponent(sub).appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: u.path) { return u }
        }
        return nil
    }
}

/// The FretOS logo (transparent), with a neon purple glow and white outline glow.
struct LogoImage: View {
    private static let image: NSImage? = Resources.url("Logo.png").flatMap(NSImage.init(contentsOf:))
    static let neon = Color(hex: 0x8A2BFF)
    var body: some View {
        if let img = Self.image {
            Image(nsImage: img).resizable().interpolation(.high).aspectRatio(contentMode: .fit)
                .shadow(color: .white.opacity(0.9), radius: 1)
                .shadow(color: Self.neon, radius: 8)
                .shadow(color: Self.neon.opacity(0.8), radius: 22)
                .accessibilityHidden(true)
        }
    }
}

/// A rectangle with stepped "pixel" corners.
struct PixelRect: InsettableShape {
    var step: CGFloat = 3
    var steps = 2
    var inset: CGFloat = 0

    func inset(by amount: CGFloat) -> PixelRect { var s = self; s.inset += amount; return s }

    func path(in r: CGRect) -> Path {
        let r = r.insetBy(dx: inset, dy: inset)
        let c = step * CGFloat(steps)
        var p = Path()
        p.move(to: CGPoint(x: r.minX + c, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX - c, y: r.minY))
        for i in 1...steps {   // top-right stair
            let k = CGFloat(i) * step
            p.addLine(to: CGPoint(x: r.maxX - c + k, y: r.minY + k - step))
            p.addLine(to: CGPoint(x: r.maxX - c + k, y: r.minY + k))
        }
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - c))
        for i in 1...steps {   // bottom-right
            let k = CGFloat(i) * step
            p.addLine(to: CGPoint(x: r.maxX - k + step, y: r.maxY - c + k))
            p.addLine(to: CGPoint(x: r.maxX - k, y: r.maxY - c + k))
        }
        p.addLine(to: CGPoint(x: r.minX + c, y: r.maxY))
        for i in 1...steps {   // bottom-left
            let k = CGFloat(i) * step
            p.addLine(to: CGPoint(x: r.minX + c - k, y: r.maxY - k + step))
            p.addLine(to: CGPoint(x: r.minX + c - k, y: r.maxY - k))
        }
        p.addLine(to: CGPoint(x: r.minX, y: r.minY + c))
        for i in 1...steps {   // top-left
            let k = CGFloat(i) * step
            p.addLine(to: CGPoint(x: r.minX + k - step, y: r.minY + c - k))
            p.addLine(to: CGPoint(x: r.minX + k, y: r.minY + c - k))
        }
        p.closeSubpath()
        return p
    }
}

/// Dark recessed panel used to group each section.
struct Panel<Content: View>: View {
    var title: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title {
                Text(title).font(Theme.pixel(8)).foregroundStyle(Theme.dim).tracking(1)
            }
            content
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PixelRect(step: 2).fill(Theme.panel))
        .overlay(PixelRect(step: 2).strokeBorder(Theme.panelEdge, lineWidth: 2))
    }
}

/// Small chunky pixel button.
struct PixelButton: View {
    var title: String
    var tint: Color = Theme.chromeTop
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(Theme.pixel(8))
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, 10).padding(.vertical, 7)
                .background(PixelRect(step: 2, steps: 1).fill(
                    LinearGradient(colors: [tint, tint.opacity(0.7)], startPoint: .top, endPoint: .bottom)))
                .overlay(PixelRect(step: 2, steps: 1).strokeBorder(Theme.chromeEdge, lineWidth: 2))
        }
        .buttonStyle(PressableStyle())
    }
}

struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.offset(y: configuration.isPressed ? 1 : 0)
            .brightness(configuration.isPressed ? -0.08 : 0)
    }
}

/// Pixel on/off switch.
struct PixelToggle: View {
    @Binding var isOn: Bool
    var onLabel = "ON", offLabel = "OFF"

    var body: some View {
        Button { isOn.toggle() } label: {
            HStack(spacing: 0) {
                Text(onLabel).frame(width: 34, height: 20)
                    .background(isOn ? Theme.fret[.green]! : Color.clear)
                    .foregroundStyle(isOn ? Theme.ink : Theme.dim)
                Text(offLabel).frame(width: 34, height: 20)
                    .background(isOn ? Color.clear : Theme.chromeBottom)
                    .foregroundStyle(isOn ? Theme.dim : Theme.ink)
            }
            .font(Theme.pixel(7))
            .background(Theme.well)
            .clipShape(PixelRect(step: 2, steps: 1))
            .overlay(PixelRect(step: 2, steps: 1).strokeBorder(Theme.panelEdge, lineWidth: 2))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isOn ? onLabel : offLabel)
    }
}
