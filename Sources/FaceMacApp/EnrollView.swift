import FaceMacCore
import SwiftUI

struct EnrollView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        let _ = model.uiLanguage
        VStack(spacing: 14) {
            ZStack {
                CameraPreview(session: CameraCapture.shared.previewSession)
                    .frame(width: 380, height: 285)
                    .background(Color.black)
                    .clipShape(RoundedRectangle(cornerRadius: 14))

                if model.isEnrolling || model.enrollJustFinished {
                    EnrollmentRing(
                        progress: model.enrollJustFinished ? 1 : Double(model.enrollStepProgress),
                        symbol: model.enrollJustFinished ? "checkmark" : model.enrollStepSymbol,
                        done: model.enrollJustFinished,
                        active: model.isEnrolling
                    )
                    .frame(width: 220, height: 220)
                }
            }

            if model.isEnrolling {
                HStack(spacing: 7) {
                    ForEach(Array(0..<model.enrollStepCount), id: \.self) { index in
                        Circle()
                            .fill(index < model.enrollStepIndex ? NotchPalette.green
                                  : index == model.enrollStepIndex ? Color.white
                                  : Color.white.opacity(0.2))
                            .frame(width: index == model.enrollStepIndex ? 9 : 7,
                                   height: index == model.enrollStepIndex ? 9 : 7)
                            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: model.enrollStepIndex)
                    }
                }
            }

            Text(model.enrollMessage)
                .font(.callout.weight(model.isEnrolling ? .semibold : .regular))
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)

            HStack {
                if model.isEnrolling {
                    Button(L10n.t("enroll.cancel")) { model.cancelEnrollment() }
                } else {
                    Button(L10n.t("enroll.start")) { model.beginEnrollment() }
                        .keyboardShortcut(.defaultAction)
                    Button(L10n.t("enroll.forget")) { model.forgetFace() }
                        .disabled(!model.hasEnrollment)
                }
            }
        }
        .padding(20)
        .frame(width: 420)
        .onAppear { model.previewAcquire() }
        .onDisappear {
            model.cancelEnrollment()
            model.previewRelease()
        }
    }
}

/// Face ID style ring: fills toward the current step, spins while listening,
/// and closes with a checkmark when the whole set is captured.
private struct EnrollmentRing: View {
    let progress: Double
    let symbol: String
    let done: Bool
    let active: Bool

    @State private var spin = false
    @State private var pulse = false
    @State private var burst = false

    var body: some View {
        ZStack {
            Circle()
                .fill(.black.opacity(0.22))

            Circle()
                .stroke(.white.opacity(0.18), lineWidth: 6)

            Circle()
                .trim(from: 0, to: done ? 1 : max(progress, 0.001))
                .stroke(NotchPalette.green, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .shadow(color: NotchPalette.green.opacity(done ? 0.6 : 0.3), radius: 7)
                .animation(.spring(response: 0.35, dampingFraction: 0.8), value: progress)
                .animation(.spring(response: 0.4, dampingFraction: 0.7), value: done)

            if active {
                Circle()
                    .trim(from: 0, to: 0.1)
                    .stroke(.white.opacity(0.5), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(spin ? 360 : 0))
            }

            Circle()
                .stroke(NotchPalette.green.opacity(burst ? 0 : 0.7), lineWidth: 2)
                .scaleEffect(burst ? 1.4 : 1.0)
                .opacity(done ? 1 : 0)

            Image(systemName: symbol)
                .font(.system(size: 42, weight: done ? .bold : .medium))
                .foregroundStyle(done ? NotchPalette.green : .white.opacity(0.95))
                .scaleEffect(done ? 1 : (pulse ? 1.06 : 0.96))
        }
        .onAppear {
            withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                spin = true
            }
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                pulse = true
            }
            if done {
                withAnimation(.easeOut(duration: 0.5)) { burst = true }
            }
        }
        .onChange(of: done) { _, isDone in
            if isDone {
                withAnimation(.easeOut(duration: 0.5)) { burst = true }
            }
        }
    }
}
