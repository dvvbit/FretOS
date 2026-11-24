// Removes a baked-in checkerboard / light background from a logo PNG.
// Flood-fills from the image border through light or glow-tinted pixels and stops at the
// art's dark outline; everything reached becomes transparent. The art's glow is re-drawn
// later by make-icon.swift, so it is removed here too.
// Usage: swift clean-logo.swift in.png out.png
import AppKit

let args = CommandLine.arguments
guard let src = NSImage(contentsOfFile: args[1]),
      let cg = src.cgImage(forProposedRect: nil, context: nil, hints: nil) else { fatalError("can't read \(args[1])") }
let w = cg.width, h = cg.height
var px = [UInt8](repeating: 0, count: w * h * 4)
let ctx = CGContext(data: &px, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))

func brightness(_ i: Int) -> Double { Double(max(px[i], px[i + 1], px[i + 2])) / 255 }
// background or glow: anything not dark. The art is enclosed by a dark outline.
// Also passes through see-through pixels, so real transparency and soft glows are handled.
func passable(_ i: Int) -> Bool { px[i + 3] < 200 || brightness(i) > 0.42 }

var bg = [Bool](repeating: false, count: w * h)
var stack: [Int] = []
for x in 0..<w { stack.append(x); stack.append((h - 1) * w + x) }
for y in 0..<h { stack.append(y * w); stack.append(y * w + w - 1) }
while let p = stack.popLast() {
    if bg[p] || !passable(p * 4) { continue }
    bg[p] = true
    let x = p % w, y = p / w
    if x > 0 { stack.append(p - 1) }
    if x < w - 1 { stack.append(p + 1) }
    if y > 0 { stack.append(p - w) }
    if y < h - 1 { stack.append(p + w) }
}
var cleared = 0
for p in 0..<(w * h) where bg[p] {
    px[p * 4] = 0; px[p * 4 + 1] = 0; px[p * 4 + 2] = 0; px[p * 4 + 3] = 0; cleared += 1
}
// Trim to the art's bounding box, padded to a square, so it can be sized predictably.
var minX = w, minY = h, maxX = 0, maxY = 0
for y in 0..<h { for x in 0..<w where px[(y * w + x) * 4 + 3] > 0 {
    minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
} }
let side = Int(Double(max(maxX - minX, maxY - minY) + 1) * 1.06)
let cx = (minX + maxX) / 2, cy = (minY + maxY) / 2
let full = ctx.makeImage()!
let square = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
                       space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
// CGContext origin is bottom-left; buffer row 0 is the top.
square.draw(full, in: CGRect(x: side / 2 - cx, y: side / 2 - (h - 1 - cy), width: w, height: h))
let out = square.makeImage()!
let rep = NSBitmapImageRep(cgImage: out)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: args[2]))
print("cleared \(cleared * 100 / (w * h))% of pixels")
