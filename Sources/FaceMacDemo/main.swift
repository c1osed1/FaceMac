import CoreMedia
import CoreVideo
import Foundation
import FaceMacCore

// facemac-demo — headless sanity checks for the recognition pipeline.
//
//   facemac-demo info                 permissions, enrollment, settings
//   facemac-demo enroll [seconds]     capture and store reference embeddings
//   facemac-demo match  [seconds]     live similarity against the enrollment
//
// Note: the camera needs a bundle with NSCameraUsageDescription to be granted
// access. Use the FaceMac.app target for real camera use; this CLI is for
// quick pipeline checks.

final class Collector: CameraCaptureDelegate {
    private let detector = FaceDetector()
    private let embedder: FaceEmbedder
    private let reference: [FaceEmbedding]
    private let threshold: Float
    private let target: Int
    private let deadline: Date

    private var frameCounter = 0
    private var samples = 0
    private var best: Float = -1
    private var done = false

    init(embedder: FaceEmbedder, reference: [FaceEmbedding], threshold: Float, target: Int, seconds: TimeInterval) {
        self.embedder = embedder
        self.reference = reference
        self.threshold = threshold
        self.target = target
        self.deadline = Date().addingTimeInterval(seconds)
    }

    func cameraCapture(_ capture: CameraCapture, didOutput pixelBuffer: CVPixelBuffer, at time: CMTime) {
        guard !done else { return }
        frameCounter += 1
        guard frameCounter % 3 == 0 else { return }

        guard
            let faces = try? detector.detect(in: pixelBuffer),
            let face = faces.max(by: { $0.area < $1.area }),
            let embedding = try? embedder.embed(FaceInput(pixelBuffer: pixelBuffer, face: face))
        else {
            return
        }

        samples += 1

        if reference.isEmpty {
            print("  sample \(samples): face detected (\(face.landmarks == nil ? "no landmarks" : "landmarks ok"))")
        } else {
            let result = FaceMatcher.match(embedding, against: reference, threshold: threshold)
            best = max(best, result.similarity)
            let verdict = result.isMatch ? "MATCH" : "no match"
            print(String(format: "  sample %d: similarity %.3f  %@", samples, result.similarity, verdict))
        }

        if samples >= target || Date() >= deadline {
            done = true
            capture.removeDelegate(self)
            capture.relinquish()
            CFRunLoopStop(CFRunLoopGetMain())
        }
    }
}

func runCollector(reference: [FaceEmbedding], target: Int, seconds: TimeInterval) {
    let capture = CameraCapture.shared
    let embedder = EmbedderFactory.make()
    AppSettings.shared.applyRecommendedThreshold(from: embedder)
    let collector = Collector(
        embedder: embedder,
        reference: reference,
        threshold: AppSettings.shared.matchThreshold,
        target: target,
        seconds: seconds
    )
    capture.addDelegate(collector)

    do {
        try capture.acquire()
    } catch {
        print("Camera unavailable: \(error)")
        print("(A bundled app with NSCameraUsageDescription is required for camera access.)")
        exit(1)
    }

    RunLoop.main.run(until: Date().addingTimeInterval(seconds + 1))
    capture.removeDelegate(collector)
    capture.relinquish()
}

let arguments = Array(CommandLine.arguments.dropFirst())
let command = arguments.first ?? "info"
let store = EnrollmentStore.shared

switch command {
case "info":
    let enrollment = try? store.load()
    let embedder = EmbedderFactory.make()
    AppSettings.shared.applyRecommendedThreshold(from: embedder)
    print("FaceMac demo")
    print("  embedder        : \(type(of: embedder)) (\(embedder.dimension)-d, threshold \(AppSettings.shared.matchThreshold))")
    print("  enrollment file : \(EnrollmentStore.defaultURL().path)")
    print("  enrolled faces  : \(enrollment?.embeddings.count ?? 0)")
    print("  saved password  : \((try? KeychainStore.shared.password()) ?? nil != nil ? "yes" : "no")")
    print("  accessibility   : \(KeyboardInjector.isAccessibilityTrusted ? "granted" : "not granted")")
    print("  screen locked   : \(LockWatcher.isScreenLocked ? "yes" : "no")")

case "enroll":
    let seconds = arguments.count > 1 ? (Double(arguments[1]) ?? 5) : 5
    print("Capturing for \(seconds)s. Look at the camera and move your head slowly.")
    let enroller = FaceEnroller(minSamples: 5, duration: seconds)

    enroller.enroll { result in
        switch result {
        case .success(let embeddings):
            do {
                try store.save(Enrollment(name: "default", embeddings: embeddings))
                print("Saved \(embeddings.count) embeddings to \(EnrollmentStore.defaultURL().path)")
            } catch {
                print("Could not save enrollment: \(error)")
            }
        case .failure(let error):
            print("Enrollment failed: \(error)")
        }
        CFRunLoopStop(CFRunLoopGetMain())
    }
    RunLoop.main.run(until: Date().addingTimeInterval(seconds + 5))

case "match":
    let seconds = arguments.count > 1 ? (Double(arguments[1]) ?? 10) : 10
    guard let enrollment = try? store.load(), !enrollment.embeddings.isEmpty else {
        print("No enrollment found. Run `facemac-demo enroll` first.")
        exit(1)
    }
    print("Comparing against \(enrollment.embeddings.count) reference embeddings for \(seconds)s.")
    runCollector(reference: enrollment.embeddings, target: 10_000, seconds: seconds)

default:
    print("""
    usage: facemac-demo <command>
      info              show permissions, enrollment and settings
      enroll [seconds]  capture and store reference face embeddings
      match  [seconds]  compare the live camera against the enrollment
    """)
}
