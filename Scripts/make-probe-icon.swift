// Draws the layers of App/Probe/AppIcon.icon (ADR-0007): a SpaceMouse cap seen from above, as in the probe's drawing
// (SpaceMouseKitUI), with its blue ring light, and the directions the probe asks for around it, drawn here (SF Symbols
// may not be used in app icons). Usage: swift Scripts/make-probe-icon.swift [App/Probe/AppIcon.icon]
import AppKit
import CoreGraphics
import Foundation

let size = 1024.0
let center = CGPoint(x: size / 2, y: size / 2)
let output = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "App/Probe/AppIcon.icon")
let assets = output.appendingPathComponent("Assets")
try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)

func gray(_ white: Double, _ alpha: Double = 1) -> CGColor { CGColor(gray: white, alpha: alpha) }
func rgb(_ hex: UInt32, _ alpha: Double = 1) -> CGColor {
    CGColor(red: Double(hex >> 16 & 0xFF) / 255, green: Double(hex >> 8 & 0xFF) / 255, blue: Double(hex & 0xFF) / 255,
            alpha: alpha)
}
func gradient(_ colors: [CGColor], _ locations: [CGFloat]? = nil) -> CGGradient {
    CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors as CFArray, locations: locations)!
}
func circle(_ radius: Double, at point: CGPoint = center) -> CGRect {
    CGRect(x: point.x - radius, y: point.y - radius, width: 2 * radius, height: 2 * radius)
}
/// A point `distance` from the centre, `degrees` clockwise from up (Core Graphics: y up).
func around(_ distance: Double, _ degrees: Double) -> CGPoint {
    let angle = degrees * .pi / 180
    return CGPoint(x: center.x + distance * sin(angle), y: center.y + distance * cos(angle))
}

func render(_ name: String, draw: (CGContext) -> Void) throws {
    let context = CGContext(data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setShouldAntialias(true)
    draw(context)
    let rep = NSBitmapImageRep(cgImage: context.makeImage()!)
    try rep.representation(using: .png, properties: [:])!.write(to: assets.appendingPathComponent(name))
}

let blue = 0x3FA0FF as UInt32          // the SpaceMouse's ring light (SpaceMouseTopView.motion)
let markColor = 0xA9D8FF as UInt32

// The body: the dark top of a SpaceMouse, filling the squircle.
try render("body.png") { c in
    c.drawLinearGradient(gradient([gray(0.25), gray(0.10)]), start: CGPoint(x: 0, y: size), end: .zero, options: [])
    c.drawRadialGradient(gradient([gray(1, 0.08), gray(1, 0)]), startCenter: CGPoint(x: 330, y: 820), startRadius: 0,
                         endCenter: CGPoint(x: 330, y: 820), endRadius: 560, options: [])
}

// The cap: its ring light underneath, the brushed ring, the rubber top.
try render("cap.png") { c in
    let ring = 300.0, top = 222.0
    // Ring light: a glow, then the ring itself.
    c.saveGState()
    c.setShadow(offset: .zero, blur: 60, color: rgb(blue, 0.9))
    c.setStrokeColor(rgb(blue))
    c.setLineWidth(18)
    c.strokeEllipse(in: circle(ring + 10))
    c.restoreGState()
    // Brushed metal ring, lit from above.
    c.saveGState()
    c.addEllipse(in: circle(ring))
    c.clip()
    c.drawLinearGradient(gradient([gray(0.78), gray(0.52), gray(0.30)], [0, 0.45, 1]),
                         start: CGPoint(x: center.x, y: center.y + ring), end: CGPoint(x: center.x, y: center.y - ring),
                         options: [])
    // Fine concentric brushing.
    c.setLineWidth(1)
    var radius = top + 4
    while radius < ring {
        c.setStrokeColor(gray(radius.truncatingRemainder(dividingBy: 6) < 3 ? 1 : 0, 0.05))
        c.strokeEllipse(in: circle(radius))
        radius += 3
    }
    c.restoreGState()
    c.setStrokeColor(gray(0, 0.5))
    c.setLineWidth(3)
    c.strokeEllipse(in: circle(ring))
    // Rubber top, slightly dished.
    c.saveGState()
    c.addEllipse(in: circle(top))
    c.clip()
    c.drawRadialGradient(gradient([gray(0.30), gray(0.16), gray(0.07)], [0, 0.6, 1]),
                         startCenter: CGPoint(x: center.x - 40, y: center.y + 60), startRadius: 0,
                         endCenter: center, endRadius: top, options: [.drawsAfterEndLocation])
    c.restoreGState()
    c.setStrokeColor(gray(0, 0.6))
    c.setLineWidth(4)
    c.strokeEllipse(in: circle(top))
}

// The directions: four chevrons around the cap (slide), two curved arrows on its upper diagonals (twist), a dot in
// the middle (push), as in the probe's drawing.
try render("directions.png") { c in
    c.setStrokeColor(rgb(markColor))
    c.setFillColor(rgb(markColor))
    c.setLineCap(.round)
    c.setLineJoin(.round)
    c.setLineWidth(30)
    for degrees in [0.0, 90, 180, 270] {
        let tip = around(420, degrees)
        c.move(to: around(375, degrees - 9))
        c.addLine(to: tip)
        c.addLine(to: around(375, degrees + 9))
        c.strokePath()
    }
    // Twist: arcs on the rim's upper diagonals, each with its head.
    c.setLineWidth(26)
    for (from, to) in [(28.0, 62.0), (-28.0, -62.0)] {
        let radius = 380.0
        let path = CGMutablePath()
        let steps = 24
        for step in 0...steps {
            let point = around(radius, from + (to - from) * Double(step) / Double(steps))
            step == 0 ? path.move(to: point) : path.addLine(to: point)
        }
        c.addPath(path)
        c.strokePath()
        // Head at `to`, pointing along the arc.
        let direction = to > from ? 1.0 : -1.0
        let tip = around(radius, to + direction * 9)
        c.move(to: around(radius + 38, to - direction * 2))
        c.addLine(to: tip)
        c.addLine(to: around(radius - 38, to - direction * 2))
        c.closePath()
        c.fillPath()
    }
    c.fillEllipse(in: circle(40))
}

let json = """
{
  "fill" : "automatic",
  "groups" : [
    {
      "layers" : [
        { "glass" : true, "image-name" : "directions.png", "name" : "directions" }
      ],
      "shadow" : { "kind" : "layer-color", "opacity" : 0.5 },
      "specular" : true,
      "translucency" : { "enabled" : false, "value" : 0 }
    },
    {
      "layers" : [
        { "glass" : false, "image-name" : "cap.png", "name" : "cap" }
      ],
      "shadow" : { "kind" : "neutral", "opacity" : 0.5 },
      "translucency" : { "enabled" : false, "value" : 0 }
    },
    {
      "layers" : [
        { "glass" : false, "image-name" : "body.png", "name" : "body" }
      ],
      "shadow" : { "kind" : "none", "opacity" : 0 },
      "translucency" : { "enabled" : false, "value" : 0 }
    }
  ],
  "supported-platforms" : {
    "squares" : [ "macOS" ]
  }
}
"""
try json.write(to: output.appendingPathComponent("icon.json"), atomically: true, encoding: .utf8)
print("wrote \(output.path)")
