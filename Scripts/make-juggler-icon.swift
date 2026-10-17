// Draws the layers of App/AppIcon.icon (ADR-0008): the menu bar symbol (MenuBarIcon, compiled in alongside) as a white
// glass mark on a blue squircle. Usage:
//   swiftc Sources/SpaceJuggler/MenuBarIcon.swift Scripts/make-juggler-icon.swift -o .build/make-juggler-icon
//   .build/make-juggler-icon [App/AppIcon.icon]
import AppKit
import CoreGraphics
import Foundation

@main
@MainActor
enum MakeJugglerIcon {
    static let size = 1024.0

    static func main() throws {
        let output = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "App/AppIcon.icon")
        let assets = output.appendingPathComponent("Assets")
        try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)

        // The background: a deep blue, lighter towards the top, set apart from Space Probe's dark body.
        try render(assets.appendingPathComponent("background.png")) { c in
            c.drawLinearGradient(gradient([rgb(0x3D8BE0), rgb(0x123C78)]), start: CGPoint(x: 0, y: size), end: .zero,
                                 options: [])
        }

        // The mark: the menu bar symbol, white, its 18 pt square scaled to 62 % of the icon and centred on what it
        // covers (base bottom 1.5, cap top 14.4).
        try render(assets.appendingPathComponent("mark.png")) { _ in
            let width = size * 0.62
            let scale = width / 18
            let middle = (1.5 + 14.4) / 2 * scale
            MenuBarIcon.draw(in: NSRect(x: (size - width) / 2, y: size / 2 - middle, width: width, height: width),
                             color: .white)
        }

        let json = """
        {
          "fill" : "automatic",
          "groups" : [
            {
              "layers" : [
                { "glass" : true, "image-name" : "mark.png", "name" : "mark" }
              ],
              "shadow" : { "kind" : "neutral", "opacity" : 0.5 },
              "specular" : true,
              "translucency" : { "enabled" : true, "value" : 0.3 }
            },
            {
              "layers" : [
                { "glass" : false, "image-name" : "background.png", "name" : "background" }
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
    }

    static func rgb(_ hex: UInt32) -> CGColor {
        CGColor(red: Double(hex >> 16 & 0xFF) / 255, green: Double(hex >> 8 & 0xFF) / 255,
                blue: Double(hex & 0xFF) / 255, alpha: 1)
    }

    static func gradient(_ colors: [CGColor]) -> CGGradient {
        CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors as CFArray, locations: nil)!
    }

    /// Renders a 1024×1024 layer; `draw` gets the context, which is also AppKit's current one.
    static func render(_ url: URL, draw: (CGContext) -> Void) throws {
        let context = CGContext(data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setShouldAntialias(true)
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        draw(context)
        NSGraphicsContext.current = nil
        let rep = NSBitmapImageRep(cgImage: context.makeImage()!)
        try rep.representation(using: .png, properties: [:])!.write(to: url)
    }
}
