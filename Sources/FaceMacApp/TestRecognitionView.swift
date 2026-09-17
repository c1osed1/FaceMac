import FaceMacCore
import SwiftUI

struct TestRecognitionView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        let _ = model.uiLanguage
        VStack(spacing: 14) {
            ZStack {
                CameraPreview(session: CameraCapture.shared.previewSession)
                    .frame(width: 360, height: 270)
                    .background(Color.black)
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                if testFaceCount == 0 {
                    Text(L10n.t("test.noFace"))
                        .font(.callout.weight(.semibold))
                        .padding(8)
                        .background(.ultraThinMaterial, in: Capsule())
                }

                if model.testMatched {
                    Text(L10n.t("test.itsYou"))
                        .font(.title2.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Color.green.opacity(0.85), in: Capsule())
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        .padding(.top, 10)
                }
            }

            VStack(spacing: 4) {
                Text(similarityText)
                    .font(.system(size: 34, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(model.testMatched ? .green : .primary)
                Text("\(L10n.t("test.threshold")) \(String(format: "%.2f", model.threshold)) · centroid \(model.testCentroid >= 0 ? String(format: "%.2f", model.testCentroid) : "--")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(L10n.t("test.hint"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(width: 340)

            Button(L10n.t("test.done")) { model.endTest() }
                .keyboardShortcut(.defaultAction)
        }
        .padding(20)
        .frame(width: 400)
        .onAppear { model.previewAcquire(); model.beginTest() }
        .onDisappear { model.endTest(); model.previewRelease() }
    }

    private var testFaceCount: Int { model.testFaceCount }

    private var similarityText: String {
        guard model.testFaceCount > 0 else { return "--" }
        guard model.testSimilarity >= 0 else { return "--" }
        return String(format: "%.2f", model.testSimilarity)
    }
}
