import CoreVideo
import Foundation
import Vision

public struct FaceEmbedding: Codable, Equatable {
    public var vector: [Float]

    public init(vector: [Float]) {
        self.vector = vector
    }
}

public struct FaceInput {
    public let pixelBuffer: CVPixelBuffer
    public let face: DetectedFace

    public init(pixelBuffer: CVPixelBuffer, face: DetectedFace) {
        self.pixelBuffer = pixelBuffer
        self.face = face
    }
}

public enum FaceEmbedderError: Error {
    case noLandmarks
    case unavailable(String)
}

/// Turns a detected face into a fixed-length, L2-normalised vector.
public protocol FaceEmbedder {
    var dimension: Int { get }
    /// Cosine threshold that suits this embedder's similarity distribution.
    var recommendedThreshold: Float { get }
    /// Identifies the preprocessing/weights, so an enrollment made with a
    /// different model is discarded instead of silently mis-matching.
    var modelTag: String { get }
    func embed(_ input: FaceInput) throws -> FaceEmbedding
}

public extension FaceEmbedder {
    var recommendedThreshold: Float { 0.5 }
    var modelTag: String { "landmark-v1" }
}

/// Default, dependency-free embedder built from Vision face landmarks.
///
/// It is deterministic and works with no model assets, but it is **not**
/// identity-grade: it is meant to get the pipeline running end to end.
/// Swap in `CoreMLEmbedder` (ArcFace/FaceNet) for real accuracy.
public struct LandmarkEmbedder: FaceEmbedder {
    public let dimension: Int

    public var recommendedThreshold: Float { 0.90 }

    private static let regions: [KeyPath<VNFaceLandmarks2D, VNFaceLandmarkRegion2D?>] = [
        \.faceContour,
        \.leftEye,
        \.rightEye,
        \.leftEyebrow,
        \.rightEyebrow,
        \.nose,
        \.noseCrest,
        \.medianLine,
        \.outerLips,
        \.innerLips,
    ]

    public init(dimension: Int = 128) {
        self.dimension = dimension
    }

    public func embed(_ input: FaceInput) throws -> FaceEmbedding {
        guard let landmarks = input.face.landmarks else {
            throw FaceEmbedderError.noLandmarks
        }

        var points: [CGPoint] = []
        for keyPath in Self.regions {
            guard let region = landmarks[keyPath: keyPath] else { continue }
            let regionPoints = region.normalizedPoints
            for index in 0..<region.pointCount {
                points.append(regionPoints[index])
            }
        }

        guard points.count >= 2 else { throw FaceEmbedderError.noLandmarks }

        let flat = points.flatMap { [Float($0.x), Float($0.y)] }
        let resampled = Self.resample(flat, to: dimension)
        return FaceEmbedding(vector: Self.l2Normalize(resampled))
    }

    static func resample(_ values: [Float], to count: Int) -> [Float] {
        guard count > 0 else { return [] }
        guard values.count > 1 else {
            return Array(repeating: values.first ?? 0, count: count)
        }
        if values.count == count { return values }

        var output = [Float](repeating: 0, count: count)
        let step = Float(values.count - 1) / Float(max(count - 1, 1))
        for index in 0..<count {
            let position = Float(index) * step
            let lower = Int(position.rounded(.down))
            let upper = min(lower + 1, values.count - 1)
            let t = position - Float(lower)
            output[index] = values[lower] * (1 - t) + values[upper] * t
        }
        return output
    }

    static func l2Normalize(_ vector: [Float]) -> [Float] {
        let norm = sqrt(vector.reduce(0) { $0 + $1 * $1 })
        guard norm > 0 else { return vector }
        return vector.map { $0 / norm }
    }
}
