import AppKit

/// The on-screen switcher: one row of app icons in Dock order, like the built-in ⌘⇥ panel.
/// It never becomes key or active, so the app you're in keeps focus until you pick another one.
final class SwitcherPanel {
    var onHover: ((Int) -> Void)?
    var onClick: ((Int) -> Void)?

    private let window: NonKeyPanel
    private var content: SwitcherContentView?
    private var mouseAtShow = NSPoint.zero

    var isVisible: Bool { window.isVisible }

    init() {
        window = NonKeyPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                             backing: .buffered, defer: true)
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.popUpMenuWindow)))
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.hidesOnDeactivate = false
        window.isReleasedWhenClosed = false
        window.animationBehavior = .none
        window.acceptsMouseMovedEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
    }

    func show(items: [SwitchItem], selected: Int) {
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }
            ?? NSScreen.main ?? NSScreen.screens.first
        guard let screen else { return }

        let view = SwitcherContentView(items: items, maxWidth: screen.visibleFrame.width * 0.92,
                                       numberPosition: Settings.numberPosition,
                                       showRunningDots: Settings.includeNotRunning,
                                       solidBackground: false)
        view.onHover = { [weak self] index in
            guard let self else { return }
            // Only react once the mouse actually moves, not because the panel opened under it.
            let now = NSEvent.mouseLocation
            if hypot(now.x - self.mouseAtShow.x, now.y - self.mouseAtShow.y) > 2 { self.onHover?(index) }
        }
        view.onClick = { [weak self] index in self?.onClick?(index) }
        view.setSelection(selected)

        let size = view.frame.size
        let visible = screen.visibleFrame
        let origin = NSPoint(x: (visible.midX - size.width / 2).rounded(),
                             y: (visible.midY - size.height / 2).rounded())
        window.contentView = view
        window.setFrame(NSRect(origin: origin, size: size), display: true)
        content = view
        mouseAtShow = NSEvent.mouseLocation
        window.orderFrontRegardless()
        window.invalidateShadow()
    }

    func setSelection(_ index: Int) {
        content?.setSelection(index)
    }

    func hide() {
        window.orderOut(nil)
        window.contentView = nil
        content = nil
    }

    /// Renders the panel into a PNG (used by `Dockstep --snapshot` to check the layout).
    static func snapshot(items: [SwitchItem], selected: Int, maxWidth: CGFloat,
                         numberPosition: NumberPosition, dark: Bool, framed: Bool = false) -> Data? {
        let view = SwitcherContentView(items: items, maxWidth: maxWidth, numberPosition: numberPosition,
                                       showRunningDots: Settings.includeNotRunning, solidBackground: true)
        view.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        view.setSelection(selected)
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return nil }
        view.cacheDisplay(in: view.bounds, to: rep)
        guard framed else { return rep.representation(using: .png, properties: [:]) }

        // Transparent margin with a soft drop shadow, like the panel floating over a window.
        let margin: CGFloat = 36
        let size = NSSize(width: view.bounds.width + 2 * margin, height: view.bounds.height + 2 * margin)
        let scale = CGFloat(rep.pixelsWide) / view.bounds.width
        guard let canvas = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale),
                                            pixelsHigh: Int(size.height * scale), bitsPerSample: 8,
                                            samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
        else { return nil }
        canvas.size = size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: canvas)
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(dark ? 0.55 : 0.25)
        shadow.shadowBlurRadius = 22
        shadow.shadowOffset = NSSize(width: 0, height: -8)
        shadow.set()
        rep.draw(in: NSRect(x: margin, y: margin, width: view.bounds.width, height: view.bounds.height),
                 from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: false, hints: nil)
        NSGraphicsContext.restoreGraphicsState()
        return canvas.representation(using: .png, properties: [:])
    }
}

final class NonKeyPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Layout: [margin][tile][tile]…[divider][tile]…[margin], with the selected app's name
/// right below the row. Each tile is the selection box itself (icon plus a hair of padding),
/// plus an optional number row. The same margin is used on all four sides:
/// panel edge → selection box (left, right, top) and app name → panel edge (bottom).
final class SwitcherContentView: NSView {
    var onHover: ((Int) -> Void)?
    var onClick: ((Int) -> Void)?

    private var tiles: [TileView] = []
    private let nameLabel = NSTextField(labelWithString: "")
    private let solidBackground: Bool

    private let margin: CGFloat = 10
    private let nameHeight: CGFloat = 16
    /// Empty space inside the name's line box below the letters; subtracted so the
    /// visible bottom margin matches the others.
    private let nameDescent: CGFloat = 3
    private var cornerRadius: CGFloat = 20

    init(items: [SwitchItem], maxWidth: CGFloat, numberPosition: NumberPosition,
         showRunningDots: Bool, solidBackground: Bool) {
        self.solidBackground = solidBackground
        super.init(frame: .zero)

        let pinnedCount = items.filter(\.isPinned).count
        let hasDivider = pinnedCount > 0 && pinnedCount < items.count
        let gap: CGFloat = 2
        let dividerWidth: CGFloat = hasDivider ? 12 : 0

        // Icons shrink to fit the screen, like the built-in switcher.
        let count = CGFloat(max(items.count, 1))
        let available = maxWidth - 2 * margin - dividerWidth - (count - 1) * gap
        let iconSize = max(24, min(88, (available / count - 2 * TileView.boxPadding).rounded(.down)))
        let cellWidth = iconSize + 2 * TileView.boxPadding
        let cellHeight = cellWidth + (numberPosition.needsRow ? TileView.numberHeight : 0)
        cornerRadius = TileView.boxRadius(for: cellWidth) + margin // concentric with the selection box

        // Bottom to top: margin, name of the selected app, the row of tiles, margin.
        let nameY = margin - nameDescent
        let tilesY = nameY + nameHeight + (numberPosition == .bottom ? 4 : 2)
        let height = tilesY + cellHeight + margin
        let width = 2 * margin + count * cellWidth + (count - 1) * gap + dividerWidth
        frame = NSRect(x: 0, y: 0, width: width.rounded(.up), height: height.rounded(.up))

        if solidBackground {
            wantsLayer = true
        } else {
            let blur = NSVisualEffectView(frame: bounds)
            blur.material = .hudWindow
            blur.blendingMode = .behindWindow
            blur.state = .active
            blur.maskImage = Self.roundedMask(radius: cornerRadius)
            blur.autoresizingMask = [.width, .height]
            addSubview(blur)
        }

        var x = margin
        for (index, item) in items.enumerated() {
            if hasDivider && index == pinnedCount {
                let line = NSBox(frame: NSRect(x: (x - gap / 2 + dividerWidth / 2).rounded(),
                                               y: tilesY + cellHeight * 0.15, width: 1, height: cellHeight * 0.7))
                line.boxType = .separator
                addSubview(line)
                x += dividerWidth
            }
            let number = index < 10 ? (index == 9 ? "0" : "\(index + 1)") : nil
            let tile = TileView(frame: NSRect(x: x, y: tilesY, width: cellWidth, height: cellHeight), item: item,
                                iconSize: iconSize, number: number, numberPosition: numberPosition,
                                showRunningDot: showRunningDots && item.isRunning)
            tile.onHover = { [weak self] in self?.onHover?(index) }
            tile.onClick = { [weak self] in self?.onClick?(index) }
            addSubview(tile)
            tiles.append(tile)
            x += cellWidth + gap
        }

        nameLabel.font = .systemFont(ofSize: 13, weight: .medium)
        nameLabel.textColor = .labelColor
        nameLabel.alignment = .center
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.frame = NSRect(x: 0, y: nameY, width: 240, height: nameHeight)
        addSubview(nameLabel)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func draw(_ dirtyRect: NSRect) {
        guard solidBackground else { return }
        NSColor.windowBackgroundColor.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: cornerRadius, yRadius: cornerRadius).fill()
    }

    func setSelection(_ index: Int) {
        for (i, tile) in tiles.enumerated() { tile.isSelected = (i == index) }
        guard tiles.indices.contains(index) else { return }
        let tile = tiles[index]
        nameLabel.stringValue = tile.name
        let labelWidth = min(260, max(120, nameLabel.intrinsicContentSize.width + 8), bounds.width - 2 * margin)
        var labelX = tile.frame.midX - labelWidth / 2
        labelX = min(max(labelX, margin), bounds.width - margin - labelWidth)
        nameLabel.frame = NSRect(x: labelX.rounded(), y: nameLabel.frame.minY, width: labelWidth, height: nameHeight)
    }

    private static func roundedMask(radius: CGFloat) -> NSImage {
        let size = NSSize(width: radius * 2 + 1, height: radius * 2 + 1)
        let image = NSImage(size: size, flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }
}

/// One app: the icon with the selection box around it, and its position number —
/// either a "⌘3" badge on the icon's top-right corner or a plain number just above or below the box.
final class TileView: NSView {
    /// Extra tile height for the number row (top/bottom only; the badge needs none).
    static let numberHeight: CGFloat = 13
    /// Selection box around the icon. macOS icons already have ~10% transparent margin
    /// around their visible shape, so 1pt more is enough breathing room.
    static let boxPadding: CGFloat = 1

    static func boxRadius(for boxWidth: CGFloat) -> CGFloat { (boxWidth * 0.2).rounded() }

    var onHover: (() -> Void)?
    var onClick: (() -> Void)?
    let name: String

    var isSelected = false {
        didSet { if isSelected != oldValue { needsDisplay = true } }
    }

    private let icon: NSImage
    private let iconAlpha: CGFloat
    private let numberText: String?
    private let numberPosition: NumberPosition
    private let iconRect: NSRect
    /// The grey selection box: the icon plus a little padding, never a number row.
    private let highlightRect: NSRect
    /// The number row, or the badge's outline.
    private let numberRect: NSRect
    private let badgeFont: NSFont
    /// Transparent margin between the icon image's edge and its visible shape.
    private let shapeInset: CGFloat
    private let showRunningDot: Bool

    init(frame: NSRect, item: SwitchItem, iconSize: CGFloat,
         number: String?, numberPosition: NumberPosition, showRunningDot: Bool) {
        self.name = item.name
        self.icon = item.icon
        self.iconAlpha = item.isRunning ? 1 : 0.45
        self.showRunningDot = showRunningDot
        self.numberPosition = numberPosition
        if let number, numberPosition.showsNumber {
            numberText = numberPosition == .badge ? "⌘" + number : number
        } else {
            numberText = nil
        }

        // The selection box fills the tile's width; a number row (top/bottom) sits right next to it.
        let boxSize = iconSize + 2 * Self.boxPadding
        highlightRect = NSRect(x: 0, y: numberPosition == .bottom ? Self.numberHeight : 0,
                               width: boxSize, height: boxSize)
        iconRect = highlightRect.insetBy(dx: Self.boxPadding, dy: Self.boxPadding)
        shapeInset = (iconSize * 0.1).rounded()

        let badgeHeight = max(13, (iconSize * 0.21).rounded())
        badgeFont = .monospacedDigitSystemFont(ofSize: (badgeHeight * 0.62).rounded(), weight: .semibold)

        switch numberPosition {
        case .badge:
            // The badge overlaps the visible shape's top-right corner like a Dock notification badge.
            let overhang = (badgeHeight * 0.3).rounded()
            let textWidth = (numberText ?? "").size(withAttributes: [.font: badgeFont]).width
            let width = max(badgeHeight, (textWidth + badgeHeight * 0.7).rounded(.up))
            numberRect = NSRect(x: iconRect.maxX - shapeInset + overhang - width,
                                y: iconRect.maxY - shapeInset + overhang - badgeHeight,
                                width: width, height: badgeHeight)
        case .top:
            numberRect = NSRect(x: 0, y: highlightRect.maxY, width: frame.width, height: Self.numberHeight)
        case .bottom:
            numberRect = NSRect(x: 0, y: 0, width: frame.width, height: Self.numberHeight)
        case .hidden, .off:
            numberRect = .zero
        }
        super.init(frame: frame)
        toolTip = item.name
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func draw(_ dirtyRect: NSRect) {
        if isSelected {
            NSColor.labelColor.withAlphaComponent(0.16).setFill()
            let radius = Self.boxRadius(for: highlightRect.width)
            NSBezierPath(roundedRect: highlightRect, xRadius: radius, yRadius: radius).fill()
        }

        icon.draw(in: iconRect, from: .zero, operation: .sourceOver, fraction: iconAlpha,
                  respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high.rawValue])

        if showRunningDot {
            NSColor.labelColor.withAlphaComponent(0.7).setFill()
            // Just under the visible icon shape, like the Dock's running indicator.
            let d: CGFloat = 4
            let y = (iconRect.minY + shapeInset / 2 - d / 2).rounded()
            NSBezierPath(ovalIn: NSRect(x: iconRect.midX - d / 2, y: y, width: d, height: d)).fill()
        }

        guard let numberText else { return }
        if numberPosition == .badge {
            drawBadge(numberText)
        } else {
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .semibold),
                .foregroundColor: isSelected ? NSColor.labelColor : NSColor.secondaryLabelColor,
            ]
            let size = numberText.size(withAttributes: attributes)
            numberText.draw(at: NSPoint(x: (numberRect.midX - size.width / 2).rounded(),
                                        y: (numberRect.midY - size.height / 2).rounded()),
                            withAttributes: attributes)
        }
    }

    /// Neutral gray "⌘3" pill that follows light/dark mode, like macOS's count badges
    /// (e.g. Mail's sidebar). The selected app's badge uses the accent color.
    private func drawBadge(_ text: String) {
        let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let fill: NSColor
        let textColor: NSColor
        let rimColor: NSColor
        if isSelected {
            fill = .controlAccentColor
            textColor = .white
            rimColor = NSColor.white.withAlphaComponent(0.2)
        } else if isDark {
            fill = NSColor(white: 0.30, alpha: 0.95)
            textColor = NSColor(white: 0.93, alpha: 1)
            rimColor = NSColor.white.withAlphaComponent(0.14)
        } else {
            fill = NSColor(white: 0.93, alpha: 0.97)
            textColor = NSColor(white: 0.25, alpha: 1)
            rimColor = NSColor.black.withAlphaComponent(0.12)
        }

        let radius = numberRect.height / 2
        let pill = NSBezierPath(roundedRect: numberRect, xRadius: radius, yRadius: radius)

        // A soft shadow lifts the badge off light icons (Safari, Chrome) and dark ones alike.
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(isDark ? 0.4 : 0.25)
        shadow.shadowBlurRadius = 2
        shadow.shadowOffset = NSSize(width: 0, height: -1)
        shadow.set()
        fill.setFill()
        pill.fill()
        NSGraphicsContext.restoreGraphicsState()

        let rim = NSBezierPath(roundedRect: numberRect.insetBy(dx: 0.5, dy: 0.5),
                               xRadius: radius - 0.5, yRadius: radius - 0.5)
        rim.lineWidth = 1
        rimColor.setStroke()
        rim.stroke()

        let attributes: [NSAttributedString.Key: Any] = [.font: badgeFont, .foregroundColor: textColor]
        let size = text.size(withAttributes: attributes)
        text.draw(at: NSPoint(x: numberRect.midX - size.width / 2, y: numberRect.midY - size.height / 2),
                  withAttributes: attributes)
    }

    /// Clicks on the icon count as clicks on the tile.
    override func hitTest(_ point: NSPoint) -> NSView? {
        frame.contains(point) ? self : nil
    }

    override func updateTrackingAreas() {
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
        super.updateTrackingAreas()
    }

    override func mouseEntered(with event: NSEvent) { onHover?() }
    override func mouseMoved(with event: NSEvent) { onHover?() }
    override func mouseDown(with event: NSEvent) { onClick?() }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
