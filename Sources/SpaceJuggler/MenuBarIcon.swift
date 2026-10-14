import AppKit

/// The menu bar symbol: a SpaceMouse seen slightly from above, the cap on its base, as a template image (one colour
/// plus alpha, so macOS tints it for light, dark and dimmed). Drawn at any scale.
enum MenuBarIcon {
    static func image(size: CGFloat = 18) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            draw(in: rect)
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Space Juggler"
        return image
    }

    /// A disc seen from slightly above: top ellipse, sides, bottom ellipse, in unit coordinates of an 18 pt square.
    private static func disc(centerX: CGFloat, bottom: CGFloat, width: CGFloat, rim: CGFloat, thickness: CGFloat,
                             scale: CGFloat) -> (whole: NSBezierPath, top: NSBezierPath) {
        func ellipse(_ y: CGFloat) -> NSRect {
            NSRect(x: (centerX - width / 2) * scale, y: y * scale, width: width * scale, height: rim * scale)
        }
        let whole = NSBezierPath(ovalIn: ellipse(bottom))
        whole.append(NSBezierPath(rect: NSRect(x: (centerX - width / 2) * scale, y: (bottom + rim / 2) * scale,
                                               width: width * scale, height: thickness * scale)))
        let top = NSBezierPath(ovalIn: ellipse(bottom + thickness))
        whole.append(top)
        return (whole, top)
    }

    private static func draw(in rect: NSRect) {
        let scale = rect.width / 18
        let base = disc(centerX: 9, bottom: 1.5, width: 16, rim: 5, thickness: 2.5, scale: scale)
        let cap = disc(centerX: 9, bottom: 5.2, width: 8.5, rim: 3.2, thickness: 6, scale: scale)

        // The base half transparent, the cap solid, with a hair of clear edge so the two separate.
        NSColor.black.withAlphaComponent(0.55).setFill()
        base.whole.fill()
        NSGraphicsContext.current?.cgContext.setBlendMode(.clear)
        cap.whole.lineWidth = 1.4 * scale
        cap.whole.stroke()
        NSGraphicsContext.current?.cgContext.setBlendMode(.normal)
        NSColor.black.setFill()
        cap.whole.fill()
        // The cap's top face, set off by a thin clear line.
        NSGraphicsContext.current?.cgContext.setBlendMode(.clear)
        cap.top.lineWidth = 0.8 * scale
        cap.top.stroke()
    }
}
