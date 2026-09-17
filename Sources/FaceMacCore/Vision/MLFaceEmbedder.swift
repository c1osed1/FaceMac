import CoreML
import CoreVideo
import Foundation
import Vision

/// Identity-grade face embedder backed by a CoreML model.
///
/// The model must take a 112x112 similarity-aligned face crop and emit a
/// fixed-length embedding (SFace emits 128-d, ArcFace 512-d). `FaceAligner`
/// produces the aligned crop the model expects, so this works with any
/// ArcFace-style network.
///
/// Drop `FaceEmbedding.mlmodelc` into the app bundle; if it is missing the app
/// falls back to `LandmarkEmbedder` via `EmbedderFactory`.
public final class MLFaceEmbedder: FaceEmbedder {
    public enum EmbedderError: Error {
        case modelNotFound(String)
        case alignmentFailed
        case invalidOutput
    }

    public let dimension: Int
    public var recommendedThreshold: Float
    public var modelTag: String { "sface-raw-v1" }

    private let model: VNCoreMLModel
    private let aligner = FaceAligner()

    public convenience init(
        modelName: String = "FaceEmbedding",
        dimension: Int = 128,
        recommendedThreshold: Float = 0.45
    ) throws {
        guard
            let url = Bundle.main.url(forResource: modelName, withExtension: "mlmodelc")
                ?? Bundle.main.url(forResource: modelName, withExtension: "mlmodel")
        else {
            throw EmbedderError.modelNotFound(modelName)
        }
        try self.init(modelURL: url, dimension: dimension, recommendedThreshold: recommendedThreshold)
    }

    public init(
        modelURL: URL,
        dimension: Int = 128,
        recommendedThreshold: Float = 0.45
    ) throws {
        let compiled = try MLModel(contentsOf: modelURL)
        self.model = try VNCoreMLModel(for: compiled)
        self.dimension = dimension
        self.recommendedThreshold = recommendedThreshold
    }

    public func embed(_ input: FaceInput) throws -> FaceEmbedding {
        guard let aligned = aligner.alignedCrop(from: input.pixelBuffer, face: input.face) else {
            throw EmbedderError.alignmentFailed
        }
        return try embedAligned(aligned)
    }

    /// Runs the model on an already-aligned 112x112 crop.
    func embedAligned(_ pixelBuffer: CVPixelBuffer) throws -> FaceEmbedding {
        let request = VNCoreMLRequest(model: model)
        request.imageCropAndScaleOption = .scaleFill

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])
        try handler.perform([request])

        guard
            let observation = request.results?.first as? VNCoreMLFeatureValueObservation,
            let multiArray = observation.featureValue.multiArrayValue
        else {
            throw EmbedderError.invalidOutput
        }

        let count = multiArray.count
        var vector = [Float](repeating: 0, count: count)
        for index in 0..<count {
            vector[index] = multiArray[index].floatValue
        }
        return FaceEmbedding(vector: LandmarkEmbedder.l2Normalize(vector))
    }
}

/// Picks the best embedder available at runtime.
public enum EmbedderFactory {
    public static func make() -> FaceEmbedder {
        if
            let path = ProcessInfo.processInfo.environment["FACEMAC_MODEL"],
            let ml = try? MLFaceEmbedder(modelURL: URL(fileURLWithPath: path))
        {
            Log.vision.info("using CoreML face embedder from FACEMAC_MODEL")
            return ml
        }
        if let ml = try? MLFaceEmbedder() {
            Log.vision.info("using CoreML face embedder")
            return ml
        }
        Log.vision.info("no CoreML model bundled, using landmark embedder")
        return LandmarkEmbedder()
    }
}
