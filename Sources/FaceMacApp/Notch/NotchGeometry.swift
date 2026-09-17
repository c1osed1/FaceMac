import AppKit

/// Where the notch lives on a given screen, and how big the surrounding
/// transparent panel needs to be.
///
/// The shape is always drawn *below* the notch housing: on the lock screen the
/// system masks the notch area and clips anything drawn inside it, so nothing
/// may rely on pixels there.
struct NotchGeometry {
    let screen: NSScreen
    let hasPhysicalNotch: Bool
    /// Width of the closed shape, matched to the real notch when there is one.
    let closedWidth: CGFloat
    /// Height of the notch housing (or the pill height on non-notched displays).
    let closedHeight: CGFloat
    /// Distance from the top edge of the screen to the top of the shape.
    let shapeTop: CGFloat
    let panelSize: CGSize

    init(screen: NSScreen) {
        self.screen = screen

        let notchHeight = screen.safeAreaInsets.top
        let hasNotch = notchHeight > 0
        self.hasPhysicalNotch = hasNotch

        if hasNotch {
            let left = screen.auxiliaryTopLeftArea?.width ?? 0
            let right = screen.auxiliaryTopRightArea?.width ?? 0
            self.closedWidth = max(screen.frame.width - left - right + 4, 120)
            self.closedHeight = notchHeight
            // Anchored to the screen top: the shape's centre top is swallowed by
            // the notch, so it reads as growing *out of* the notch.
            self.shapeTop = 0
        } else {
            let menuBarHeight = max(screen.frame.maxY - screen.visibleFrame.maxY, 24)
            self.closedWidth = 200
            self.closedHeight = 24
            self.shapeTop = menuBarHeight + 6
        }

        self.panelSize = CGSize(
            width: max(closedWidth + 240, 480),
            height: 320
        )
    }

    var panelFrame: CGRect {
        let frame = screen.frame
        let origin = CGPoint(
            x: (frame.midX - panelSize.width / 2).rounded(),
            y: (frame.maxY - shapeTop - panelSize.height).rounded()
        )
        return CGRect(origin: origin, size: panelSize)
    }

    /// A window frame that fits the shape exactly, so an interactive notch does
    /// not swallow clicks in the transparent area around it.
    func shapeFrame(width: CGFloat, height: CGFloat) -> CGRect {
        let frame = screen.frame
        let origin = CGPoint(
            x: (frame.midX - width / 2).rounded(),
            y: (frame.maxY - shapeTop - height).rounded()
        )
        return CGRect(origin: origin, size: CGSize(width: width, height: height))
    }

    static func preferred() -> NotchGeometry? {
        let screen = NSScreen.screens.first { $0.safeAreaInsets.top > 0 }
            ?? NSScreen.main
            ?? NSScreen.screens.first
        guard let screen else { return nil }
        return NotchGeometry(screen: screen)
    }
}
