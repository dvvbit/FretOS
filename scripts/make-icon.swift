// Builds FretOS's app icon from the cleaned logo (transparent PNG):
// dark rounded-square tile (macOS icon grid: 824px tile on 1024 canvas), soft purple
// glow behind the art, thin chrome rim. Usage: swift make-icon.swift logo.png out.png
import AppKit
import CoreImage

let args = CommandLine.arguments
guard let logo = NSImage(contentsOfFile: args[1]) else { fatalError("can't read \(args[1])") }
let size = 1024, tile: CGFloat = 824, radius: CGFloat = 185
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                           bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let g = NSGraphicsContext.current!
let origin = (CGFloat(size) - tile) / 2
let rect = NSRect(x: origin, y: origin, width: tile, height: tile)
let shape = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)

g.saveGraphicsState()                                   // tile + drop shadow
let drop = NSShadow(); drop.shadowColor = NSColor.black.withAlphaComponent(0.35)
drop.shadowBlurRadius = 18; drop.shadowOffset = NSSize(width: 0, height: -8); drop.set()
NSColor(srgbRed: 0.05, green: 0.05, blue: 0.06, alpha: 1).setFill(); shape.fill()
g.restoreGraphicsState()

g.saveGraphicsState()
shape.addClip()
let art = rect.insetBy(dx: tile * 0.13, dy: tile * 0.13)
// Neon glow: the logo's silhouette filled purple, blurred, stacked.
let logoCG = logo.cgImage(forProposedRect: nil, context: nil, hints: nil)!
let silhouette = CIImage(cgImage: logoCG)
    .applyingFilter("CIColorMatrix", parameters: [
        "inputRVector": CIVector(x: 0, y: 0, z: 0, w: 0), "inputGVector": CIVector(x: 0, y: 0, z: 0, w: 0),
        "inputBVector": CIVector(x: 0, y: 0, z: 0, w: 0), "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
        "inputBiasVector": CIVector(x: 0.50, y: 0.10, z: 1.0, w: 0)])
    .premultiplyingAlpha()
let ci = CIContext()
let pad = CGFloat(logoCG.width) * 0.25
for (radius, alpha) in [(70.0, 1.0), (30.0, 1.0), (12.0, 0.9)] {
    // pad with transparent pixels (clampedToExtent would smear edge pixels into streaks)
    let canvas = silhouette.extent.insetBy(dx: -pad, dy: -pad)
    let blurred = silhouette.composited(over: CIImage(color: .clear).cropped(to: canvas))
        .applyingFilter("CIMorphologyMaximum", parameters: ["inputRadius": CGFloat(logoCG.width) * 0.03])
        .applyingGaussianBlur(sigma: radius).cropped(to: canvas)
    let img = ci.createCGImage(blurred, from: blurred.extent)!
    let scale = art.width / CGFloat(logoCG.width)
    let r = NSRect(x: art.minX - pad * scale, y: art.minY - pad * scale,
                   width: art.width + 2 * pad * scale, height: art.height + 2 * pad * scale)
    NSImage(cgImage: img, size: r.size).draw(in: r, from: .zero, operation: .sourceOver, fraction: alpha)
}
// Crisp white outline (the style of the original art): silhouette grown a few pixels, in white.
let outlineWidth = CGFloat(logoCG.width) * 0.014
let outlineImg = CIImage(cgImage: logoCG)
    .applyingFilter("CIColorMatrix", parameters: [
        "inputRVector": CIVector(x: 0, y: 0, z: 0, w: 0), "inputGVector": CIVector(x: 0, y: 0, z: 0, w: 0),
        "inputBVector": CIVector(x: 0, y: 0, z: 0, w: 0), "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
        "inputBiasVector": CIVector(x: 1, y: 1, z: 1, w: 0)])
    .premultiplyingAlpha()
let outlineCanvas = outlineImg.extent
let grown = outlineImg.composited(over: CIImage(color: .clear).cropped(to: outlineCanvas))
    .applyingFilter("CIMorphologyMaximum", parameters: ["inputRadius": outlineWidth]).cropped(to: outlineCanvas)
NSImage(cgImage: ci.createCGImage(grown, from: outlineCanvas)!, size: art.size)
    .draw(in: art, from: .zero, operation: .sourceOver, fraction: 1)
logo.draw(in: art, from: .zero, operation: .sourceOver, fraction: 1)
g.restoreGraphicsState()

NSColor(calibratedWhite: 0.62, alpha: 0.9).setStroke()   // chrome rim
let rim = NSBezierPath(roundedRect: rect.insetBy(dx: 3, dy: 3), xRadius: radius - 3, yRadius: radius - 3)
rim.lineWidth = 6; rim.stroke()
NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: args[2]))
