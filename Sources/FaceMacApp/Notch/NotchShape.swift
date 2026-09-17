import SwiftUI

/// The notch silhouette: concave ("inverted") top corners that blend into the
/// screen edge, convex rounded bottom corners.
///
/// `animatableData` carries both radii so SwiftUI can interpolate the shape as
/// the notch opens and closes.
///
/// Independent implementation; the notch-overlay approach is inspired by Atoll
/// (GPL-3.0, https://github.com/Ebullioscopic/Atoll). See the project LICENSE.
struct NotchShape: Shape {
    var topRadius: CGFloat
    var bottomRadius: CGFloat

    init(topRadius: CGFloat = 6, bottomRadius: CGFloat = 14) {
        self.topRadius = topRadius
        self.bottomRadius = bottomRadius
    }

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topRadius, bottomRadius) }
        set {
            topRadius = newValue.first
            bottomRadius = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let top = min(topRadius, rect.width / 2, rect.height)
        let bottom = min(bottomRadius, max(0, rect.width / 2 - top), max(0, rect.height - top))

        var path = Path()

        // Top-left tip, curving inward to the left wall.
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + top, y: rect.minY + top),
            control: CGPoint(x: rect.minX + top, y: rect.minY)
        )

        // Left wall down to the bottom-left corner.
        path.addLine(to: CGPoint(x: rect.minX + top, y: rect.maxY - bottom))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + top + bottom, y: rect.maxY),
            control: CGPoint(x: rect.minX + top, y: rect.maxY)
        )

        // Bottom edge.
        path.addLine(to: CGPoint(x: rect.maxX - top - bottom, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - top, y: rect.maxY - bottom),
            control: CGPoint(x: rect.maxX - top, y: rect.maxY)
        )

        // Right wall back up, then the top-right tip.
        path.addLine(to: CGPoint(x: rect.maxX - top, y: rect.minY + top))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY),
            control: CGPoint(x: rect.maxX - top, y: rect.minY)
        )

        path.closeSubpath()
        return path
    }
}
