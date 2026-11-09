import AppKit

/// The menu bar icon: a small, single-color version of the app icon — three tiles on a
/// Dock shelf, hops from tile to tile, and the selected (last) tile filled in.
/// It's a template image, so macOS tints it for light and dark menu bars.
enum MenuBarIcon {
    static let size = NSSize(width: 18, height: 18)

    static func make() -> NSImage {
        let image = NSImage(size: size, flipped: false) { _ in
            draw()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Dockstep"
        return image
    }

    /// Draws in an 18×18 pt space, origin bottom-left. Only the alpha channel matters.
    static func draw() {
        NSColor.black.setFill()
        NSColor.black.setStroke()
        let lift: CGFloat = 1.6 // moves the whole motif up so it sits centred in the menu bar

        // Dock shelf
        NSBezierPath(roundedRect: NSRect(x: 0.5, y: 1 + lift, width: 17, height: 1.6), xRadius: 0.8, yRadius: 0.8).fill()

        // Tiles: outlined, the selected one filled.
        let tile: CGFloat = 4.2
        let gap: CGFloat = 1.6
        let firstX = (size.width - (3 * tile + 2 * gap)) / 2
        let tileY = 3.4 + lift
        var centers: [CGFloat] = []
        for i in 0..<3 {
            let rect = NSRect(x: firstX + CGFloat(i) * (tile + gap), y: tileY, width: tile, height: tile)
            centers.append(rect.midX)
            if i == 2 {
                NSBezierPath(roundedRect: rect, xRadius: 1.1, yRadius: 1.1).fill()
            } else {
                let outline = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: 0.9, yRadius: 0.9)
                outline.lineWidth = 1
                outline.stroke()
            }
        }

        // Hops from tile to tile, ending in an open arrowhead on the selected tile.
        let base = tileY + tile + 1.6
        let height: CGFloat = 9 // quadratic control height; the arc peaks at half of it
        let hops = NSBezierPath()
        hops.lineWidth = 1.4
        hops.lineCapStyle = .round
        hops.lineJoinStyle = .round
        hops.move(to: NSPoint(x: centers[0], y: base))
        var end = NSPoint.zero
        var control = NSPoint.zero
        for i in 0..<2 {
            let start = NSPoint(x: centers[i], y: base)
            end = NSPoint(x: centers[i + 1], y: base)
            control = NSPoint(x: (start.x + end.x) / 2, y: base + height)
            // Quadratic curve expressed as a cubic (NSBezierPath has no quadratic segment).
            hops.curve(to: end,
                       controlPoint1: NSPoint(x: start.x + 2 / 3 * (control.x - start.x),
                                              y: start.y + 2 / 3 * (control.y - start.y)),
                       controlPoint2: NSPoint(x: end.x + 2 / 3 * (control.x - end.x),
                                              y: end.y + 2 / 3 * (control.y - end.y)))
        }
        let angle = atan2(end.y - control.y, end.x - control.x)
        for side in [-1.0, 1.0] {
            let a = angle + .pi + side * .pi / 5
            hops.move(to: end)
            hops.line(to: NSPoint(x: end.x + cos(a) * 2.8, y: end.y + sin(a) * 2.8))
        }
        hops.stroke()
    }
}
