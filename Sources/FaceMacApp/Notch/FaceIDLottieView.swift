import AppKit
import Lottie
import SwiftUI

/// Renders the Face ID Lottie, played from the start (scan circles → tick).
///
/// Two quirks handled here:
/// * Lottie derives its scale from the view's frame, so the view is given a real
///   size before the animation is configured — otherwise it blows up.
/// * The artwork only fills the middle of its 440x370 canvas, so the animation
///   view is zoomed and centred inside a masking container to make the visible
///   circles match the size of the drawn face glyph.
struct FaceIDLottieView: NSViewRepresentable {
    /// The tick is fully drawn around frame 130; after that everything fades to
    /// nothing, so we stop there to leave the checkmark on screen.
    static let endFrame: CGFloat = 130
    static var duration: TimeInterval { Double(endFrame) / 60 }

    static var isAvailable: Bool {
        LottieAnimation.named("FaceID", bundle: .main) != nil
    }

    func makeNSView(context: Context) -> LottieContainerView {
        let container = LottieContainerView()
        container.wantsLayer = true
        container.layer?.masksToBounds = true

        let lottie = LottieAnimationView(animation: LottieAnimation.named("FaceID", bundle: .main))
        lottie.frame = CGRect(x: 0, y: 0, width: 200, height: 200)
        lottie.contentMode = .scaleAspectFit
        lottie.backgroundBehavior = .pauseAndRestore
        lottie.loopMode = .playOnce
        lottie.wantsLayer = true
        container.install(lottie)

        lottie.play(fromFrame: 0, toFrame: Self.endFrame, loopMode: .playOnce) { finished in
            guard finished else { return }
            lottie.pause()
            lottie.currentFrame = Self.endFrame
        }
        return container
    }

    func updateNSView(_ nsView: LottieContainerView, context: Context) {}
}

/// Keeps the Lottie zoomed in and centred, so the artwork fills the view.
final class LottieContainerView: NSView {
    private var lottie: LottieAnimationView?
    /// How much to enlarge the animation view so its visible content fills us.
    private let zoom: CGFloat = 1.8

    func install(_ view: LottieAnimationView) {
        lottie = view
        addSubview(view)
        needsLayout = true
    }

    override func layout() {
        super.layout()
        guard let lottie else { return }
        let side = max(bounds.width, bounds.height) * zoom
        lottie.frame = CGRect(
            x: bounds.midX - side / 2,
            y: bounds.midY - side / 2,
            width: side,
            height: side
        )
    }
}
