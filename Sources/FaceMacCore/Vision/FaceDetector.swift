import CoreVideo
import Foundation
import ImageIO
import Vision

public struct DetectedFace {
    /// Normalised bounding box in Vision coordinates (origin bottom-left).
    public let boundingBox: CGRect
    public let landmarks: VNFaceLandmarks2D?
    public let roll: Float
    public let yaw: Float
    public let pitch: Float

    public init(
        boundingBox: CGRect,
        landmarks: VNFaceLandmarks2D?,
        roll: Float,
        yaw: Float,
        pitch: Float
    ) {
        self.boundingBox = boundingBox
        self.landmarks = landmarks
        self.roll = roll
        self.yaw = yaw
        self.pitch = pitch
    }

    public var area: CGFloat { boundingBox.width * boundingBox.height }
}

public enum FaceDetectorError: Error {
    case requestFailed(Error)
}

/// Apple Vision based face detection + 2D landmarks. No model assets required.
public final class FaceDetector {
    public init() {}

    public func detect(
        in pixelBuffer: CVPixelBuffer,
        orientation: CGImagePropertyOrientation = .up
    ) throws -> [DetectedFace] {
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: orientation, options: [:])
        let request = VNDetectFaceLandmarksRequest()

        do {
            try handler.perform([request])
        } catch {
            throw FaceDetectorError.requestFailed(error)
        }

        guard let results = request.results else { return [] }

        return results.map { observation in
            DetectedFace(
                boundingBox: observation.boundingBox,
                landmarks: observation.landmarks,
                roll: observation.roll?.floatValue ?? 0,
                yaw: observation.yaw?.floatValue ?? 0,
                pitch: observation.pitch?.floatValue ?? 0
            )
        }
    }
}
