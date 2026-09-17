import CoreMedia
import CoreVideo
import Foundation

/// Captures a short burst from the camera and records face embeddings for enrollment.
public final class FaceEnroller: CameraCaptureDelegate {
    public enum EnrollError: Error {
        case noFaceDetected
        case cancelled
    }

    public typealias Completion = (Result<[FaceEmbedding], Error>) -> Void

    private let capture: CameraCapture
    private let detector = FaceDetector()
    private let embedder: FaceEmbedder
    private let minSamples: Int
    private let duration: TimeInterval

    private var startedAt: Date?
    private var frameCounter = 0
    private var embeddings: [FaceEmbedding] = []
    private var completion: Completion?
    private var finished = false

    public init(
        embedder: FaceEmbedder = EmbedderFactory.make(),
        minSamples: Int = 6,
        duration: TimeInterval = 8,
        capture: CameraCapture = .shared
    ) {
        self.embedder = embedder
        self.minSamples = minSamples
        self.duration = duration
        self.capture = capture
    }

    /// Reports the number of distinct samples captured so far.
    public var onProgress: ((Int) -> Void)?
    /// Reports the number of faces currently visible (0 or more) for guidance.
    public var onFaceCount: ((Int) -> Void)?

    public var targetSamples: Int { minSamples }

    public func enroll(completion: @escaping Completion) {
        self.completion = completion
        self.embeddings = []
        self.frameCounter = 0
        self.finished = false
        self.startedAt = Date()
        capture.addDelegate(self)

        do {
            try capture.acquire()
        } catch {
            finish(.failure(error))
        }
    }

    public func cancel() {
        guard !finished else { return }
        finish(.failure(EnrollError.cancelled))
    }

    public func cameraCapture(_ capture: CameraCapture, didOutput pixelBuffer: CVPixelBuffer, at time: CMTime) {
        DispatchQueue.main.async { [weak self] in
            self?.process(pixelBuffer)
        }
    }

    private func process(_ pixelBuffer: CVPixelBuffer) {
        guard !finished else { return }

        frameCounter += 1
        guard frameCounter % 3 == 0 else { return }

        guard let faces = try? detector.detect(in: pixelBuffer) else { return }
        onFaceCount?(faces.count)

        if let face = faces.max(by: { $0.area < $1.area }),
           let embedding = try? embedder.embed(FaceInput(pixelBuffer: pixelBuffer, face: face)) {
            embeddings.append(embedding)
            onProgress?(embeddings.count)
        }

        let elapsed = Date().timeIntervalSince(startedAt ?? Date())
        if embeddings.count >= minSamples || elapsed >= duration {
            if embeddings.isEmpty {
                finish(.failure(EnrollError.noFaceDetected))
            } else {
                finish(.success(embeddings))
            }
        }
    }

    private func finish(_ result: Result<[FaceEmbedding], Error>) {
        guard !finished else { return }
        finished = true
        capture.removeDelegate(self)
        capture.relinquish()
        let completion = self.completion
        self.completion = nil
        DispatchQueue.main.async {
            completion?(result)
        }
    }
}
