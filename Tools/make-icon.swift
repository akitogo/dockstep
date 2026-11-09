// Draws the Dockstep app icon and writes Resources/AppIcon.icns.
//
//   swiftc Tools/make-icon.swift -o /tmp/make-icon && /tmp/make-icon [out.icns] [preview-dir]
//
// The motif: a Dock shelf with four app tiles, arrows stepping from tile to tile
// in Dock order, and the third tile selected like in the switcher.
import AppKit

let arguments = CommandLine.arguments
let outputPath = arguments.count > 1 ? arguments[1] : "Resources/AppIcon.icns"
let previewDir = arguments.count > 2 ? arguments[2] : nil

func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

func rounded(_ rect: CGRect, _ radius: CGFloat) -> CGPath {
    CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

func gradient(_ colors: [CGColor], _ locations: [CGFloat]) -> CGGradient {
    CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors as CFArray, locations: locations)!
}

/// Draws the icon in a 1024×1024 coordinate space (origin bottom-left).
func drawIcon(in cg: CGContext) {
    // macOS icon grid: 824×824 body with ~22% corner radius, centred on the canvas.
    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let bodyPath = rounded(body, 185)

    cg.saveGState()
    cg.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: rgb(0x000000, 0.28))
    cg.addPath(bodyPath)
    cg.setFillColor(rgb(0x3346E0))
    cg.fillPath()
    cg.restoreGState()

    cg.saveGState()
    cg.addPath(bodyPath)
    cg.clip()
    cg.drawLinearGradient(gradient([rgb(0x72B4FF), rgb(0x4166EE), rgb(0x2B2DB5)], [0, 0.55, 1]),
                          start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])
    cg.drawRadialGradient(gradient([rgb(0xFFFFFF, 0.28), rgb(0xFFFFFF, 0)], [0, 1]),
                          startCenter: CGPoint(x: 512, y: 930), startRadius: 0,
                          endCenter: CGPoint(x: 512, y: 930), endRadius: 560, options: [])

    // Dock shelf (the whole motif is centred vertically: shelf bottom ≈ 330, arc tops ≈ 670)
    let shelf = CGRect(x: 162, y: 330, width: 700, height: 100)
    cg.addPath(rounded(shelf, 50))
    cg.setFillColor(rgb(0xFFFFFF, 0.22))
    cg.fillPath()
    cg.addPath(rounded(shelf.insetBy(dx: 1.5, dy: 1.5), 48.5))
    cg.setStrokeColor(rgb(0xFFFFFF, 0.4))
    cg.setLineWidth(3)
    cg.strokePath()

    // App tiles standing on the shelf
    let tileSize: CGFloat = 138
    let spacing: CGFloat = 28
    let firstX = 512 - (4 * tileSize + 3 * spacing) / 2
    let tileY: CGFloat = 362
    let tileColors: [(top: UInt32, bottom: UInt32)] = [
        (0xFF9A8A, 0xF0533F), // coral
        (0xFFD978, 0xF5A623), // amber
        (0x74E8AE, 0x1FB070), // green
        (0xD2B3FF, 0x8B57F5), // violet
    ]
    let selected = 2
    var tiles: [CGRect] = []
    for i in 0..<4 {
        let tile = CGRect(x: firstX + CGFloat(i) * (tileSize + spacing), y: tileY, width: tileSize, height: tileSize)
        tiles.append(tile)

        if i == selected {
            cg.addPath(rounded(tile.insetBy(dx: -16, dy: -16), 46))
            cg.setFillColor(rgb(0xFFFFFF, 0.38))
            cg.fillPath()
        }

        let path = rounded(tile, 32)
        cg.saveGState()
        cg.setShadow(offset: CGSize(width: 0, height: -6), blur: 12, color: rgb(0x0A1060, 0.35))
        cg.addPath(path)
        cg.setFillColor(rgb(tileColors[i].bottom))
        cg.fillPath()
        cg.restoreGState()

        cg.saveGState()
        cg.addPath(path)
        cg.clip()
        cg.drawLinearGradient(gradient([rgb(tileColors[i].top), rgb(tileColors[i].bottom)], [0, 1]),
                              start: CGPoint(x: tile.midX, y: tile.maxY), end: CGPoint(x: tile.midX, y: tile.minY),
                              options: [])
        cg.restoreGState()
    }

    // Steps: arcs hopping from tile to tile, the last one ending in an open arrowhead
    // that points down into the selected tile.
    let arcBase = tileY + tileSize + 34
    let lift: CGFloat = 270 // a quadratic arc peaks at half its control height
    cg.setStrokeColor(rgb(0xFFFFFF))
    cg.setLineWidth(20)
    cg.setLineCap(.round)
    cg.setLineJoin(.round)
    let arcs = CGMutablePath()
    var lastEnd = CGPoint.zero
    var lastControl = CGPoint.zero
    for i in 0..<selected {
        let start = CGPoint(x: tiles[i].midX, y: arcBase)
        let end = CGPoint(x: tiles[i + 1].midX, y: arcBase)
        let control = CGPoint(x: (start.x + end.x) / 2, y: arcBase + lift)
        if i == 0 { arcs.move(to: start) }
        arcs.addQuadCurve(to: end, control: control)
        lastEnd = end
        lastControl = control
    }
    // Open chevron along the final arc's direction, drawn from the arc's tip.
    let angle = atan2(lastEnd.y - lastControl.y, lastEnd.x - lastControl.x)
    let arm: CGFloat = 70
    let spread: CGFloat = .pi / 5
    for side in [-1.0, 1.0] {
        let a = angle + .pi + side * spread
        arcs.move(to: lastEnd)
        arcs.addLine(to: CGPoint(x: lastEnd.x + cos(a) * arm, y: lastEnd.y + sin(a) * arm))
    }
    cg.addPath(arcs)
    cg.strokePath()

    cg.restoreGState()
}

func render(pixels: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let cg = NSGraphicsContext.current!.cgContext
    cg.interpolationQuality = .high
    cg.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
    drawIcon(in: cg)
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let fm = FileManager.default
let iconset = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("AppIcon.iconset")
try? fm.removeItem(at: iconset)
try fm.createDirectory(at: iconset, withIntermediateDirectories: true)
for points in [16, 32, 128, 256, 512] {
    try render(pixels: points).write(to: iconset.appendingPathComponent("icon_\(points)x\(points).png"))
    try render(pixels: points * 2).write(to: iconset.appendingPathComponent("icon_\(points)x\(points)@2x.png"))
}
if let previewDir {
    for pixels in [1024, 128, 64, 32, 16] {
        try render(pixels: pixels).write(to: URL(fileURLWithPath: previewDir).appendingPathComponent("icon-\(pixels).png"))
    }
}

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", outputPath]
try iconutil.run()
iconutil.waitUntilExit()
guard iconutil.terminationStatus == 0 else { print("iconutil failed"); exit(1) }
print("Wrote \(outputPath)")
