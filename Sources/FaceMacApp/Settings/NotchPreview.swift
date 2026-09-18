import FaceMacCore
import SwiftUI

/// Inline, looping preview of the notch: scan → success, using the real views.
struct NotchPreview: View {
    var showsText: Bool = true

    private enum Phase { case scanning, success, rejected }
    @State private var phase: Phase = .scanning

    var body: some View {
        VStack(spacing: 12) {
            ZStack(alignment: .top) {
                NotchShape(topRadius: 10, bottomRadius: 30)
                    .fill(Color.black)
                    .frame(width: 300, height: 92)

                Group {
                    switch phase {
                    case .success:
                        HStack(spacing: 10) {
                            successAnimation
                            if showsText {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(L10n.t("notch.itsYou"))
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(.white)
                                    Text(String(format: L10n.t("notch.match"), 98))
                                        .font(.system(size: 11, weight: .medium, design: .rounded))
                                        .monospacedDigit()
                                        .foregroundStyle(.white.opacity(0.5))
                                }
                            }
                        }
                    case .scanning:
                        FaceScanView()
                    case .rejected:
                        HStack(spacing: 10) {
                            FaceScanView(tint: .red, showsSweep: false)
                            if showsText {
                                Text(L10n.t("notch.notYou"))
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(.red)
                            }
                        }
                        .modifier(Shake())
                    }
                }
                .frame(width: 300, height: 92)
            }
            .frame(maxWidth: .infinity)

            Text(caption)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 6)
        .task {
            while !Task.isCancelled {
                phase = .scanning
                try? await Task.sleep(for: .seconds(2.0))
                guard !Task.isCancelled else { return }
                phase = .success
                try? await Task.sleep(for: .seconds(2.8))
                guard !Task.isCancelled else { return }
                phase = .rejected
                try? await Task.sleep(for: .seconds(1.8))
            }
        }
    }

    private var caption: String {
        switch phase {
        case .scanning: return L10n.t("notch.looking")
        case .success: return L10n.t("notch.itsYou")
        case .rejected: return L10n.t("notch.notYou")
        }
    }

    @ViewBuilder
    private var successAnimation: some View {
        if FaceIDLottieView.isAvailable {
            FaceIDLottieView()
                .frame(width: 58, height: 58)
        } else {
            Image(systemName: "checkmark")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(NotchPalette.green)
        }
    }
}
