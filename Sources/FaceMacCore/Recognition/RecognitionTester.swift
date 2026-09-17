import CoreMedia
import CoreVideo
import Foundation

/// Live "does it recognise me?" probe for the UI. Runs the same detect → align →
/// embed → match path as the unlock flow, without typing anything.
public final class RecognitionTester: CameraCaptureDelegate {
    public struct Reading {
        public let similarity: Float
        public let centroidSimilarity: Float
        public let isMatch: Bool
        public let faceCount: Int
    }

    public var onReading: ((Reading) -> Void)?
    public var onError: ((Error) -> Void)?

    private let capture: CameraCapture
    private let detector = FaceDetector()
    private let embedder: FaceEmbedder
    private let store: EnrollmentStore

    private var references: [FaceEmbedding] = []
    private var centroid: FaceEmbedding?
    private var frameCounter = 0
    private var running = false
    private var bestSimilarity: Float = -1

    public init(
        embedder: FaceEmbedder = EmbedderFactory.make(),
        store: EnrollmentStore = .shared,
        capture: CameraCapture = .shared
    ) {
        self.embedder = embedder
        self.store = store
        self.capture = capture
    }

    public func start() {
        guard !running else { return }
        guard
            let enrollment = try? store.load(),
            !enrollment.embeddings.isEmpty,
            enrollment.modelTag == embedder.modelTag
        else {
            onError?(EnrollmentStoreError.noEnrollment)
            return
        }
        references = enrollment.embeddings
        centroid = enrollment.centroid
        frameCounter = 0
        bestSimilarity = -1
        running = true
        capture.addDelegate(self)

        do {
            try capture.acquire()
        } catch {
            running = false
            capture.removeDelegate(self)
            onError?(error)
        }
    }

    public func stop() {
        guard running else { return }
        running = false
        capture.removeDelegate(self)
        capture.relinquish()
    }

    public func cameraCapture(_ capture: CameraCapture, didOutput pixelBuffer: CVPixelBuffer, at time: CMTime) {
        DispatchQueue.main.async { [weak self] in
            self?.process(pixelBuffer)
        }
    }

    private func process(_ pixelBuffer: CVPixelBuffer) {
        guard running else { return }
        frameCounter += 1
        guard frameCounter % 3 == 0 else { return }

        guard let faces = try? detector.detect(in: pixelBuffer), !faces.isEmpty else {
            onReading?(Reading(similarity: -1, centroidSimilarity: -1, isMatch: false, faceCount: 0))
            return
        }
        guard
            let face = faces.max(by: { $0.area < $1.area }),
            face.area >= 0.02,
            let embedding = try? embedder.embed(FaceInput(pixelBuffer: pixelBuffer, face: face))
        else {
            onReading?(Reading(similarity: -1, centroidSimilarity: -1, isMatch: false, faceCount: faces.count))
            return
        }

        let threshold = AppSettings.shared.matchThreshold
        let result = FaceMatcher.match(embedding, against: references, threshold: threshold)
        let toCentroid = FaceMatcher.similarity(embedding, toCentroid: centroid ?? FaceEmbedding(vector: []))
        bestSimilarity = max(bestSimilarity, result.similarity)
        onReading?(Reading(
            similarity: result.similarity,
            centroidSimilarity: toCentroid,
            isMatch: result.isMatch && toCentroid >= threshold - 0.06,
            faceCount: faces.count
        ))
    }
}

public enum EnrollmentStoreError: Error {
    case noEnrollment
}
