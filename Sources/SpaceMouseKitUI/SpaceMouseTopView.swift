import SpaceMouseKit
import SwiftUI

/// A SpaceMouse seen from above, cable at the top (up in the drawing is forward, away from the user): the cap with its
/// twelve directions and, for the models that have them, the two side buttons. From Stagehand's virtual remote
/// (stagehand ADR-0084): chevrons around the cap = slide, dots on its rim = tilt, curved arrows on the rim's upper
/// diagonals = twist, a dot in the middle = push, a ring = pull. A direction is blue as far as the cap moves that way.
/// Every model is drawn as this body; it shows the cap, not the model.
///
/// Geometry in multiples of the body's width, snapped to whole points, even diameters around whole-point centres: on a
/// 1× display anything in between smears edges and symbols.
public struct SpaceMouseTopView: View {
    public var axes: SpaceMouseAxes
    /// Raw value at full deflection (`SpaceMouseModel.axisFullScale`).
    public var fullScale: Int
    /// The side buttons held; nil draws none (models whose keys are not the two side buttons).
    public var sideButtons: (left: Bool, right: Bool)?
    /// A direction to point at (the one asked for), drawn orange.
    public var asked: SpaceMouseAxes.Direction?
    /// Directions already done, drawn green while the cap does not move them.
    public var done: Set<SpaceMouseAxes.Direction>

    public init(axes: SpaceMouseAxes, fullScale: Int = SpaceMouseAxes.deviceFullScale,
                sideButtons: (left: Bool, right: Bool)? = nil, asked: SpaceMouseAxes.Direction? = nil,
                done: Set<SpaceMouseAxes.Direction> = []) {
        self.axes = axes
        self.fullScale = fullScale
        self.sideButtons = sideButtons
        self.asked = asked
        self.done = done
    }

    /// The blue of the device's ring, for the cap moving a way.
    static let motion = Color(red: 0.25, green: 0.62, blue: 1.0)

    public var body: some View {
        GeometryReader { proxy in
            let side = max(40, min(proxy.size.width, proxy.size.height))
            drawing(Grid(width: side - side.truncatingRemainder(dividingBy: 2)))
                .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(accessibilityText))
    }

    private var accessibilityText: String {
        guard let strongest = axes.strongest else { return "SpaceMouse cap at rest" }
        return "SpaceMouse cap: \(strongest.instruction.lowercased()), \(Int(axes.fraction(strongest, fullScale: fullScale) * 100)) %"
    }

    private struct Grid {
        let width: CGFloat
        func at(_ fraction: CGFloat) -> CGFloat { (fraction * width).rounded() }
        func even(_ fraction: CGFloat) -> CGFloat { max(2, (fraction * width / 2).rounded() * 2) }
    }

    private func drawing(_ g: Grid) -> some View {
        let height = g.at(1.0)
        let shape = RoundedRectangle(cornerRadius: g.at(0.16), style: .continuous)
        let capOuter = g.even(0.60), capInner = g.even(0.44)
        let center = CGPoint(x: g.at(0.5), y: (height / 2).rounded())
        return ZStack(alignment: .topLeading) {
            LinearGradient(colors: [Color(white: 0.20), Color(white: 0.12)], startPoint: .top, endPoint: .bottom)
            // The cable leaves at the top edge.
            Capsule().fill(Color(white: 0.32)).frame(width: g.even(0.10), height: max(3, g.at(0.028)))
                .position(x: center.x, y: g.at(0.024))
            // The cap: brushed ring around a rubber top.
            Circle().fill(LinearGradient(colors: [Color(white: 0.58), Color(white: 0.30)], startPoint: .top, endPoint: .bottom))
                .overlay(Circle().strokeBorder(.black.opacity(0.6), lineWidth: 1))
                .frame(width: capOuter, height: capOuter).position(center)
            Circle().fill(RadialGradient(colors: [Color(white: 0.28), Color(white: 0.10)], center: .center, startRadius: 0,
                                         endRadius: capInner / 2))
                .overlay(Circle().strokeBorder(.black.opacity(0.4), lineWidth: 1))
                .frame(width: capInner, height: capInner).position(center)
            capMarks(center: center, radius: CGFloat(capOuter) / 2)
            if let sideButtons {
                sideButton(sideButtons.left, g).position(x: g.at(0.085), y: center.y)
                sideButton(sideButtons.right, g).position(x: g.width - g.at(0.085), y: center.y)
            }
        }
        .frame(width: g.width, height: height)
        .clipShape(shape)
        .overlay(shape.strokeBorder(Color(white: 0.36), lineWidth: 1))
    }

    /// The twelve directions around `center`, scaled to the cap's outer `radius`.
    private func capMarks(center: CGPoint, radius: CGFloat) -> some View {
        func even(_ length: CGFloat) -> CGFloat { max(2, (length / 2).rounded() * 2) }
        /// A point `distance` (in cap radii) from the centre, `degrees` clockwise from up.
        func around(_ distance: CGFloat, _ degrees: Double) -> CGPoint {
            let angle = degrees * .pi / 180
            return CGPoint(x: (center.x + distance * radius * sin(angle)).rounded(),
                           y: (center.y - distance * radius * cos(angle)).rounded())
        }
        let chevron = (radius / 6).rounded(), dot = even(radius / 10), hit = even(radius * 0.233)
        let slides: [(SpaceMouseAxes.Direction, Double)] = [(.slideForward, 0), (.slideRight, 90), (.slideBack, 180), (.slideLeft, 270)]
        let tilts: [(SpaceMouseAxes.Direction, Double)] = [(.tiltForward, 0), (.tiltRight, 90), (.tiltBack, 180), (.tiltLeft, 270)]
        let twists: [(SpaceMouseAxes.Direction, String, Double)] = [(.twistRight, "arrow.clockwise", 45),
                                                                  (.twistLeft, "arrow.counterclockwise", -45)]
        return ZStack(alignment: .topLeading) {
            ForEach(slides, id: \.0) { direction, degrees in
                mark(direction, size: hit) { color, _ in
                    Image(systemName: "chevron.up").font(.system(size: chevron, weight: .bold)).foregroundStyle(color)
                        .rotationEffect(.degrees(degrees))
                }
                .position(around(1.15, degrees))
            }
            ForEach(tilts, id: \.0) { direction, degrees in
                mark(direction, size: hit) { color, level in
                    Circle().fill(color).frame(width: dot + (4 * level).rounded(), height: dot + (4 * level).rounded())
                }
                .position(around(0.85, degrees))
            }
            ForEach(twists, id: \.0) { direction, symbol, degrees in
                mark(direction, size: hit) { color, _ in
                    Image(systemName: symbol).font(.system(size: chevron, weight: .semibold)).foregroundStyle(color)
                }
                .position(around(0.85, degrees))
            }
            mark(.pull, size: even(radius * 0.733)) { color, level in
                Circle().strokeBorder(color, lineWidth: max(1.5, (radius * 0.0267).rounded()) + CGFloat(2 * level))
                    .frame(width: even(radius * 0.667), height: even(radius * 0.667))
            }
            .position(center)
            mark(.push, size: even(radius * 0.3)) { color, level in
                Circle().fill(color)
                    .frame(width: even(radius / 6) + (6 * level).rounded(), height: even(radius / 6) + (6 * level).rounded())
            }
            .position(center)
        }
    }

    /// One direction: blue as far as the cap moves that way, else orange when asked for, green when done, grey.
    private func mark<Label: View>(_ direction: SpaceMouseAxes.Direction, size: CGFloat,
                                   @ViewBuilder label: (Color, Double) -> Label) -> some View {
        let level = axes.fraction(direction, fullScale: fullScale)
        let color: Color = level > 0 ? Self.motion.opacity(0.35 + 0.65 * level)
            : direction == asked ? .orange
            : done.contains(direction) ? .green
            : Color(white: 0.62)
        return label(color, level).frame(width: size, height: size)
    }

    private func sideButton(_ down: Bool, _ g: Grid) -> some View {
        let shape = RoundedRectangle(cornerRadius: g.at(0.035), style: .continuous)
        return shape
            .fill(down ? AnyShapeStyle(Color.orange)
                  : AnyShapeStyle(LinearGradient(colors: [Color(white: 0.30), Color(white: 0.16)], startPoint: .top, endPoint: .bottom)))
            .overlay(shape.strokeBorder(.black.opacity(0.6), lineWidth: 1))
            .frame(width: g.at(0.09), height: g.at(0.42))
    }
}

#Preview {
    SpaceMouseTopView(axes: SpaceMouseAxes(x: 200, rz: -120), sideButtons: (true, false), asked: .tiltForward,
                      done: [.slideLeft, .push])
        .frame(width: 240, height: 240)
        .padding()
}
