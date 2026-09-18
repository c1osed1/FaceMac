import FaceMacCore
import Foundation
import SwiftUI

struct NotchView: View {
    @ObservedObject var presenter: NotchPresenter

    var body: some View {
        VStack(spacing: 0) {
            NotchShape(topRadius: presenter.topRadius, bottomRadius: presenter.bottomRadius)
                .fill(presenter.shapeFill)
                .frame(width: presenter.width, height: presenter.height)
                .overlay { contentLayer }
                .clipShape(NotchShape(topRadius: presenter.topRadius, bottomRadius: presenter.bottomRadius))
                .compositingGroup()
                .padding(.top, presenter.topInset)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(presenter.spring, value: presenter.phase)
    }

    /// Content lives in the band below the notch housing, never inside it.
    private var contentLayer: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: presenter.contentTopInset)
            Spacer(minLength: 0)
            content
            Spacer(minLength: 0)
        }
        .frame(width: presenter.width, height: presenter.height)
    }

    @ViewBuilder
    private var successAnimation: some View {
        if FaceIDLottieView.isAvailable {
            FaceIDLottieView()
                .frame(width: 66, height: 66)
                .transition(.opacity.combined(with: .scale(scale: 0.88)))
        } else {
            SuccessMorph()
                .transition(.opacity.combined(with: .scale(scale: 0.88)))
        }
    }

    @ViewBuilder
    private var content: some View {
        switch presenter.phase {
        case .hidden:
            EmptyView()

        case .scanning:
            FaceScanView()
                .transition(.opacity.combined(with: .scale(scale: 0.88)))

        case .matched(let similarity):
            HStack(spacing: 10) {
                successAnimation
                if presenter.showsMatchText {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(L10n.t("notch.itsYou"))
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                        Text(String(format: L10n.t("notch.match"), Int((similarity * 100).rounded())))
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.white.opacity(0.5))
                    }
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
                }
            }

        case .failed(let reason):
            HStack(spacing: 10) {
                FaceScanView(tint: .orange, showsSweep: false)
                if presenter.showsMatchText {
                    Text(reason.isEmpty ? L10n.t("notch.notRecognised") : reason)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .fixedSize()
                }
            }
            .modifier(Shake())
            .transition(.opacity.combined(with: .scale(scale: 0.88)))

        case .rejected(let reason):
            HStack(spacing: 10) {
                FaceScanView(tint: .red, showsSweep: false)
                if presenter.showsMatchText {
                    Text(reason.isEmpty ? L10n.t("notch.notYou") : reason)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.red)
                        .fixedSize()
                }
            }
            .modifier(Shake())
            .transition(.opacity.combined(with: .scale(scale: 0.88)))
        }
    }
}

/// Face-scan motif: four corner brackets around a face, drawn from scratch in
/// the system green. Not Apple artwork and not the MacGaze logo asset.
struct FaceScanShape: Shape {
    func path(in rect: CGRect) -> Path {
        let scale = min(rect.width, rect.height) / 100
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * scale, y: rect.minY + y * scale)
        }

        var path = Path()

        // Corner brackets.
        path.move(to: point(6, 34)); path.addLine(to: point(6, 20))
        path.addQuadCurve(to: point(20, 6), control: point(6, 6))
        path.addLine(to: point(34, 6))

        path.move(to: point(66, 6)); path.addLine(to: point(80, 6))
        path.addQuadCurve(to: point(94, 20), control: point(94, 6))
        path.addLine(to: point(94, 34))

        path.move(to: point(94, 66)); path.addLine(to: point(94, 80))
        path.addQuadCurve(to: point(80, 94), control: point(94, 94))
        path.addLine(to: point(66, 94))

        path.move(to: point(34, 94)); path.addLine(to: point(20, 94))
        path.addQuadCurve(to: point(6, 80), control: point(6, 94))
        path.addLine(to: point(6, 66))

        // Eyes.
        path.move(to: point(35, 40)); path.addLine(to: point(35, 49))
        path.move(to: point(65, 40)); path.addLine(to: point(65, 49))

        // Nose.
        path.move(to: point(50, 38))
        path.addLine(to: point(50, 55))
        path.addQuadCurve(to: point(43, 61), control: point(50, 61))

        // Smile.
        path.move(to: point(36, 73))
        path.addQuadCurve(to: point(64, 73), control: point(50, 84))

        return path
    }
}

enum NotchPalette {
    static let green = Color(red: 0x30 / 255.0, green: 0xD1 / 255.0, blue: 0x58 / 255.0)
}

struct FaceScanView: View {
    var tint: Color = NotchPalette.green
    /// The up/down sweep line reads as "actively looking"; it is dropped for the
    /// failure and rejection states.
    var showsSweep: Bool = true

    @State private var breathe = false
    @State private var sweep: CGFloat = -17

    private let side: CGFloat = 54
    private let lineWidth: CGFloat = 3.0

    var body: some View {
        ZStack {
            FaceScanShape()
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
                .frame(width: side, height: side)
                .scaleEffect(breathe ? 1.06 : 0.97)

            if showsSweep {
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [.clear, tint.opacity(0.95), .clear],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: side, height: 2.0)
                    .offset(y: sweep)
                    .mask(RoundedRectangle(cornerRadius: 10, style: .continuous).frame(width: side, height: side))
            }
        }
        .frame(width: side, height: side)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                breathe = true
            }
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                sweep = 17
            }
        }
    }
}

/// iPhone-like success: the scan brackets collapse while a checkmark draws on.
struct SuccessMorph: View {
    @State private var progress: CGFloat = 0

    var body: some View {
        ZStack {
            FaceScanShape()
                .stroke(
                    NotchPalette.green,
                    style: StrokeStyle(lineWidth: 2.8, lineCap: .round, lineJoin: .round)
                )
                .frame(width: 42, height: 42)
                .scaleEffect(1 - 0.45 * progress)
                .opacity(Double(max(0, 1 - progress * 1.7)))

            CheckmarkShape()
                .trim(from: 0, to: progress)
                .stroke(
                    NotchPalette.green,
                    style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round)
                )
                .frame(width: 26, height: 26)
        }
        .frame(width: 44, height: 44)
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.68)) {
                progress = 1
            }
        }
    }
}

private struct CheckmarkShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + rect.width * 0.10, y: rect.minY + rect.height * 0.55))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.38, y: rect.minY + rect.height * 0.82))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.90, y: rect.minY + rect.height * 0.20))
        return path
    }
}

/// Left-right shake used for a confident rejection.
struct Shake: ViewModifier {
    @State private var offset: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .offset(x: offset)
            .onAppear {
                let steps: [CGFloat] = [-8, 8, -6, 6, -3, 3, 0]
                for (index, value) in steps.enumerated() {
                    DispatchQueue.main.asyncAfter(deadline: .now() + Double(index) * 0.055) {
                        withAnimation(.linear(duration: 0.055)) { offset = value }
                    }
                }
            }
    }
}
