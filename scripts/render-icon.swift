// Renders Utter's app icon: a violet-to-coral squircle with a white waveform.
//
//   swift scripts/render-icon.swift <output-1024.png>
//
// scripts/make-icon.sh turns that PNG into Resources/AppIcon.icns.
import AppKit

let output = CommandLine.arguments.dropFirst().first ?? "icon-1024.png"
let pixels = 1024

guard
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
    let context = NSGraphicsContext(bitmapImageRep: rep)
else { fatalError("Couldn't create the drawing context") }

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = context

// macOS icon grid: an 824 pt rounded square centred on a 1024 canvas.
let tile = NSRect(x: 100, y: 100, width: 824, height: 824)
let squircle = NSBezierPath(roundedRect: tile, xRadius: 186, yRadius: 186)

let shadow = NSShadow()
shadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
shadow.shadowBlurRadius = 28
shadow.shadowOffset = NSSize(width: 0, height: -12)
NSGraphicsContext.saveGraphicsState()
shadow.set()
NSColor.black.setFill()
squircle.fill()
NSGraphicsContext.restoreGraphicsState()

let gradient = NSGradient(colors: [
    NSColor(srgbRed: 0.40, green: 0.33, blue: 0.98, alpha: 1),
    NSColor(srgbRed: 0.75, green: 0.32, blue: 0.86, alpha: 1),
    NSColor(srgbRed: 1.00, green: 0.45, blue: 0.48, alpha: 1),
])!
gradient.draw(in: squircle, angle: -55)

// Soft highlight on the top half.
NSGraphicsContext.saveGraphicsState()
squircle.addClip()
NSGradient(colors: [NSColor.white.withAlphaComponent(0.18), NSColor.white.withAlphaComponent(0)])!
    .draw(in: NSRect(x: tile.minX, y: tile.midY, width: tile.width, height: tile.height / 2), angle: -90)
NSGraphicsContext.restoreGraphicsState()

// Waveform: seven rounded bars, tallest in the middle.
let heights: [CGFloat] = [0.20, 0.38, 0.62, 0.86, 0.62, 0.38, 0.20]
let barWidth: CGFloat = 58
let gap: CGFloat = 34
let totalWidth = CGFloat(heights.count) * barWidth + CGFloat(heights.count - 1) * gap
var x = tile.midX - totalWidth / 2
NSColor.white.setFill()
for fraction in heights {
    let height = 520 * fraction
    let bar = NSRect(x: x, y: tile.midY - height / 2, width: barWidth, height: height)
    NSBezierPath(roundedRect: bar, xRadius: barWidth / 2, yRadius: barWidth / 2).fill()
    x += barWidth + gap
}

NSGraphicsContext.restoreGraphicsState()

guard let png = rep.representation(using: .png, properties: [:]) else { fatalError("PNG encoding failed") }
try png.write(to: URL(fileURLWithPath: output))
print("Wrote \(output)")
