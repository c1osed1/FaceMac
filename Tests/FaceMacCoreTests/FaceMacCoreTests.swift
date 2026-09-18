import CoreGraphics
import CoreVideo
import XCTest
@testable import FaceMacCore

final class FaceMatcherTests: XCTestCase {
    func testCosineOfIdenticalVectorsIsOne() {
        let a: [Float] = [0.2, 0.4, 0.6, 0.8]
        XCTAssertEqual(FaceMatcher.cosine(a, a), 1.0, accuracy: 0.0001)
    }

    func testCosineOfOrthogonalVectorsIsZero() {
        XCTAssertEqual(FaceMatcher.cosine([1, 0], [0, 1]), 0.0, accuracy: 0.0001)
    }

    func testCosineRejectsMismatchedDimensions() {
        XCTAssertEqual(FaceMatcher.cosine([1, 2, 3], [1, 2]), 0.0)
    }

    func testMatchRespectsThreshold() {
        let candidate = FaceEmbedding(vector: [1, 0, 0])
        let enrolled = [FaceEmbedding(vector: [0, 1, 0]), FaceEmbedding(vector: [1, 0, 0])]

        let strict = FaceMatcher.match(candidate, against: enrolled, threshold: 0.99)
        XCTAssertTrue(strict.isMatch)
        XCTAssertEqual(strict.bestIndex, 1)

        let impossible = FaceMatcher.match(candidate, against: enrolled, threshold: 1.01)
        XCTAssertFalse(impossible.isMatch)
    }

    func testMatchWithNoReferences() {
        let result = FaceMatcher.match(FaceEmbedding(vector: [1, 0]), against: [], threshold: 0.5)
        XCTAssertFalse(result.isMatch)
        XCTAssertNil(result.bestIndex)
    }
}

final class LandmarkEmbedderTests: XCTestCase {
    func testResampleProducesRequestedLength() {
        let resampled = LandmarkEmbedder.resample([0, 1, 2, 3, 4], to: 8)
        XCTAssertEqual(resampled.count, 8)
        XCTAssertEqual(resampled.first ?? -1, 0, accuracy: 0.0001)
        XCTAssertEqual(resampled.last ?? -1, 4, accuracy: 0.0001)
    }

    func testResampleHandlesShortInput() {
        XCTAssertEqual(LandmarkEmbedder.resample([], to: 4).count, 4)
        XCTAssertEqual(LandmarkEmbedder.resample([7], to: 3), [7, 7, 7])
    }

    func testL2NormalizeGivesUnitLength() {
        let normalized = LandmarkEmbedder.l2Normalize([3, 4])
        XCTAssertEqual(normalized, [0.6, 0.8])
    }

    func testL2NormalizeLeavesZeroVectorAlone() {
        XCTAssertEqual(LandmarkEmbedder.l2Normalize([0, 0, 0]), [0, 0, 0])
    }
}

final class FaceAlignerTests: XCTestCase {
    func testSimilarityIdentity() throws {
        let points = [CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 0), CGPoint(x: 0, y: 1)]
        let transform = try XCTUnwrap(FaceAligner.estimateSimilarity(from: points, to: points))
        XCTAssertEqual(transform.a, 1, accuracy: 1e-9)
        XCTAssertEqual(transform.b, 0, accuracy: 1e-9)
        XCTAssertEqual(transform.tx, 0, accuracy: 1e-9)
        XCTAssertEqual(transform.ty, 0, accuracy: 1e-9)
    }

    func testSimilarityScaleAndTranslation() throws {
        let source = [CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 0), CGPoint(x: 0, y: 1)]
        let destination = source.map { CGPoint(x: $0.x * 2 + 5, y: $0.y * 2 - 3) }
        let transform = try XCTUnwrap(FaceAligner.estimateSimilarity(from: source, to: destination))
        XCTAssertEqual(transform.a, 2, accuracy: 1e-9)
        XCTAssertEqual(transform.b, 0, accuracy: 1e-9)
        XCTAssertEqual(transform.tx, 5, accuracy: 1e-9)
        XCTAssertEqual(transform.ty, -3, accuracy: 1e-9)
    }

    func testSimilarityRotation() throws {
        let source = [CGPoint(x: 1, y: 0), CGPoint(x: 0, y: 1)]
        let destination = [CGPoint(x: 0, y: 1), CGPoint(x: -1, y: 0)]
        let transform = try XCTUnwrap(FaceAligner.estimateSimilarity(from: source, to: destination))
        XCTAssertEqual(transform.a, 0, accuracy: 1e-9)
        XCTAssertEqual(transform.b, 1, accuracy: 1e-9)
    }

    func testSimilarityRejectsMismatchedInput() {
        XCTAssertNil(FaceAligner.estimateSimilarity(from: [CGPoint.zero], to: [CGPoint.zero, CGPoint(x: 1, y: 1)]))
    }

    func testInverseRoundTrip() throws {
        let transform = SimilarityTransform(a: 1.3, b: -0.4, tx: 12, ty: -7)
        let inverse = try XCTUnwrap(transform.inverted)
        let point = CGPoint(x: 3.5, y: -2.25)
        let roundTripped = inverse.apply(transform.apply(point))
        XCTAssertEqual(roundTripped.x, point.x, accuracy: 1e-9)
        XCTAssertEqual(roundTripped.y, point.y, accuracy: 1e-9)
    }

    func testWarpKeepsSolidColor() throws {
        let buffer = try makeBuffer(width: 24, height: 24, r: 10, g: 120, b: 240)
        let warped = try XCTUnwrap(
            FaceAligner.warp(buffer, transform: SimilarityTransform(a: 1, b: 0, tx: 0, ty: 0), size: 8)
        )

        CVPixelBufferLockBaseAddress(warped, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(warped, .readOnly) }
        let base = try XCTUnwrap(CVPixelBufferGetBaseAddress(warped)).assumingMemoryBound(to: UInt8.self)

        XCTAssertEqual(Double(base[0]), 240, accuracy: 1)
        XCTAssertEqual(Double(base[1]), 120, accuracy: 1)
        XCTAssertEqual(Double(base[2]), 10, accuracy: 1)
        XCTAssertEqual(base[3], 255)
    }
}

final class MLFaceEmbedderTests: XCTestCase {
    private var modelURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Resources/FaceEmbedding.mlmodelc")
    }

    func testBundledModelProducesUnitEmbedding() throws {
        guard FileManager.default.fileExists(atPath: modelURL.path) else {
            throw XCTSkip("FaceEmbedding.mlmodelc not built; run scripts/fetch-model.sh")
        }

        let embedder = try MLFaceEmbedder(modelURL: modelURL)
        let buffer = try makeBuffer(width: 112, height: 112, r: 200, g: 150, b: 120)
        let embedding = try embedder.embedAligned(buffer)

        XCTAssertEqual(embedder.dimension, 128)
        XCTAssertEqual(embedding.vector.count, 128)

        let norm = sqrt(embedding.vector.reduce(0) { $0 + $1 * $1 })
        XCTAssertEqual(norm, 1, accuracy: 1e-3)
    }

    /// Guards the whole Swift preprocessing path (32BGRA buffer → Vision → CoreML)
    /// against the ONNX reference. A mismatch here means the colour channels are
    /// being fed in the wrong order, which makes every face look similar.
    func testPreprocessingMatchesONNXReference() throws {
        guard FileManager.default.fileExists(atPath: modelURL.path) else {
            throw XCTSkip("FaceEmbedding.mlmodelc not built; run scripts/fetch-model.sh")
        }

        let golden: [Float] = [
            0.027914, 0.058380, -0.082477, 0.036523, 0.063750, 0.037254, -0.054277, -0.036526,
            -0.010492, -0.084864, -0.033916, 0.006671, -0.066645, -0.079647, 0.049980, -0.037390,
            -0.038562, 0.020619, -0.195872, 0.131781, -0.096321, -0.089054, 0.102243, 0.010856,
            0.057440, 0.120625, 0.040788, 0.166440, -0.041498, 0.065767, -0.009891, 0.029959,
            0.105334, -0.048621, 0.144771, -0.000381, 0.093903, 0.094813, -0.103670, 0.126551,
            -0.009871, -0.161542, 0.074864, 0.048198, 0.023495, 0.143967, -0.012734, 0.028861,
            0.088039, -0.080277, 0.069550, -0.038248, 0.039853, -0.085705, -0.101444, 0.058923,
            0.007744, 0.150136, -0.024365, 0.182898, -0.067311, -0.031008, -0.185422, 0.006538,
            0.039159, 0.095525, 0.075836, 0.015694, 0.025175, -0.033861, 0.177938, -0.101825,
            -0.084950, -0.053395, 0.043795, 0.055955, -0.009024, -0.029025, -0.091292, 0.098765,
            0.159478, 0.047687, 0.016953, -0.021300, 0.060201, 0.080711, 0.238952, -0.040008,
            -0.000519, -0.023014, -0.031788, 0.157982, 0.235003, 0.166636, -0.065112, 0.025587,
            -0.136346, 0.005349, -0.042205, 0.073603, 0.076402, -0.080867, 0.062289, -0.071217,
            0.086790, -0.012942, 0.025392, 0.104220, 0.099118, -0.166022, -0.063452, -0.118705,
            0.118954, -0.079809, -0.045717, 0.009085, 0.014395, -0.021562, -0.000446, -0.056434,
            -0.018559, -0.111502, 0.044543, 0.149357, 0.136680, -0.127950, 0.110596, 0.030168,
        ]

        let embedder = try MLFaceEmbedder(modelURL: modelURL)
        let buffer = try makePatternBuffer()
        let actual = try embedder.embedAligned(buffer).vector

        let cosine = FaceMatcher.cosine(actual, golden)
        XCTAssertGreaterThan(
            cosine, 0.999,
            "Swift preprocessing diverges from the ONNX reference (cosine \(cosine)) — colour order is likely wrong"
        )
    }

    /// (x*2, y*2, x+y) per channel; the golden vector above was produced by the
    /// ONNX model on the same pattern.
    private func makePatternBuffer() throws -> CVPixelBuffer {
        var buffer: CVPixelBuffer?
        let width = 112
        let height = 112
        CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA, nil, &buffer)
        let pixelBuffer = try XCTUnwrap(buffer)

        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }
        let base = try XCTUnwrap(CVPixelBufferGetBaseAddress(pixelBuffer)).assumingMemoryBound(to: UInt8.self)
        let stride = CVPixelBufferGetBytesPerRow(pixelBuffer)

        for y in 0..<height {
            for x in 0..<width {
                let offset = y * stride + x * 4
                base[offset + 0] = UInt8((x + y) % 256)      // B
                base[offset + 1] = UInt8((y * 2) % 256)      // G
                base[offset + 2] = UInt8((x * 2) % 256)      // R
                base[offset + 3] = 255
            }
        }
        return pixelBuffer
    }
}

private func makeBuffer(width: Int, height: Int, r: UInt8, g: UInt8, b: UInt8) throws -> CVPixelBuffer {
    var buffer: CVPixelBuffer?
    CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA, nil, &buffer)
    let pixelBuffer = try XCTUnwrap(buffer)

    CVPixelBufferLockBaseAddress(pixelBuffer, [])
    defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }
    let base = try XCTUnwrap(CVPixelBufferGetBaseAddress(pixelBuffer)).assumingMemoryBound(to: UInt8.self)
    let stride = CVPixelBufferGetBytesPerRow(pixelBuffer)

    for y in 0..<height {
        for x in 0..<width {
            let offset = y * stride + x * 4
            base[offset + 0] = b
            base[offset + 1] = g
            base[offset + 2] = r
            base[offset + 3] = 255
        }
    }
    return pixelBuffer
}

final class ThresholdCalibrationTests: XCTestCase {
    func testCentroidOfRepeatedSampleMatchesIt() {
        let sample = FaceEmbedding(vector: LandmarkEmbedder.l2Normalize([0.3, -0.4, 0.7, 0.1]))
        let enrollment = Enrollment(name: "t", embeddings: [sample, sample, sample])
        XCTAssertEqual(FaceMatcher.cosine(enrollment.centroid.vector, sample.vector), 1.0, accuracy: 1e-4)
    }

    func testSelfSimilarityIsOneForIdenticalSamples() {
        let sample = FaceEmbedding(vector: LandmarkEmbedder.l2Normalize([0.5, 0.5, 0.5, 0.5]))
        let enrollment = Enrollment(name: "t", embeddings: [sample, sample, sample])
        XCTAssertEqual(enrollment.selfSimilarity, 1.0, accuracy: 1e-4)
    }

    func testCalibrationStaysInSafeRange() {
        // Very consistent samples must not push the threshold above 0.80.
        let sample = FaceEmbedding(vector: LandmarkEmbedder.l2Normalize([1, 0, 0, 0]))
        let tight = Enrollment(name: "t", embeddings: [sample, sample, sample])
        let tightResult = ThresholdCalibration.calibrate(from: tight)
        XCTAssertLessThanOrEqual(tightResult.threshold, 0.65)
        XCTAssertGreaterThanOrEqual(tightResult.threshold, 0.40)

        // Noisy samples must not push it below the floor either.
        let noisy = Enrollment(name: "t", embeddings: [
            FaceEmbedding(vector: LandmarkEmbedder.l2Normalize([1, 0, 0, 0])),
            FaceEmbedding(vector: LandmarkEmbedder.l2Normalize([0, 1, 0, 0])),
        ])
        XCTAssertGreaterThanOrEqual(ThresholdCalibration.calibrate(from: noisy).threshold, 0.40)
    }

    func testCentroidEmptyEnrollment() {
        XCTAssertTrue(Enrollment(name: "t", embeddings: []).centroid.vector.isEmpty)
    }
}

final class EnrollmentStoreTests: XCTestCase {
    func testRoundTrip() throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("facemac-test-\(UUID().uuidString).json")
        let store = EnrollmentStore(fileURL: url)
        defer { try? FileManager.default.removeItem(at: url) }

        XCTAssertNil(try store.load())

        let enrollment = Enrollment(name: "tester", embeddings: [FaceEmbedding(vector: [0.1, 0.2, 0.3])])
        try store.save(enrollment)

        let loaded = try XCTUnwrap(try store.load())
        XCTAssertEqual(loaded, enrollment)

        try store.delete()
        XCTAssertNil(try store.load())
    }
}

final class LivenessTrackerTests: XCTestCase {
    func testModeCombinations() {
        XCTAssertTrue(LivenessTracker.isLive(mode: .off, blink: false, motion: false))
        XCTAssertFalse(LivenessTracker.isLive(mode: .blink, blink: false, motion: true))
        XCTAssertTrue(LivenessTracker.isLive(mode: .blink, blink: true, motion: false))
        XCTAssertFalse(LivenessTracker.isLive(mode: .motion, blink: true, motion: false))
        XCTAssertTrue(LivenessTracker.isLive(mode: .motion, blink: false, motion: true))
        XCTAssertTrue(LivenessTracker.isLive(mode: .blinkOrMotion, blink: true, motion: false))
        XCTAssertTrue(LivenessTracker.isLive(mode: .blinkOrMotion, blink: false, motion: true))
        XCTAssertFalse(LivenessTracker.isLive(mode: .blinkOrMotion, blink: false, motion: false))
        XCTAssertTrue(LivenessTracker.isLive(mode: .blinkAndMotion, blink: true, motion: true))
        XCTAssertFalse(LivenessTracker.isLive(mode: .blinkAndMotion, blink: true, motion: false))
        XCTAssertFalse(LivenessTracker.isLive(mode: .blinkAndMotion, blink: false, motion: true))
    }

    func testModeStoredValueFallsBack() {
        XCTAssertEqual(LivenessMode(storedValue: "blink"), .blink)
        XCTAssertEqual(LivenessMode(storedValue: "nonsense"), .blinkOrMotion)
        XCTAssertEqual(LivenessMode(storedValue: nil), .blinkOrMotion)
    }

    func testMeanDisplacementIdenticalIsZero() {
        let points = [CGPoint(x: 0.2, y: 0.3), CGPoint(x: 0.7, y: 0.6)]
        XCTAssertEqual(LivenessTracker.meanDisplacement(from: points, to: points), 0)
    }

    func testMeanDisplacementAveragesDistances() {
        let a = [CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 1)]
        let b = [CGPoint(x: 3, y: 0), CGPoint(x: 1, y: 2)]
        // distances: 3 and 1 -> mean 2
        XCTAssertEqual(LivenessTracker.meanDisplacement(from: a, to: b), 2, accuracy: 0.0001)
    }

    func testMeanDisplacementRejectsMismatchedCounts() {
        XCTAssertEqual(
            LivenessTracker.meanDisplacement(from: [CGPoint(x: 0, y: 0)], to: []),
            0
        )
    }

    func testPoseDeltaSumsAbsoluteChanges() {
        let delta = LivenessTracker.poseDelta(
            from: (yaw: 0, pitch: 0, roll: 0),
            to: (yaw: 0.5, pitch: -0.25, roll: 1)
        )
        XCTAssertEqual(delta, 1.75, accuracy: 0.0001)
    }

    func testSignatureAndRatioHandleMissingLandmarks() {
        XCTAssertTrue(LivenessTracker.motionSignature(nil).isEmpty)
        XCTAssertNil(LivenessTracker.eyeAspectRatio(nil, imageSize: CGSize(width: 100, height: 100)))
    }

    func testTrackerConfirmsAfterReset() {
        let tracker = LivenessTracker()
        tracker.reset()
        XCTAssertFalse(tracker.isConfirmed(for: .blinkOrMotion))
        XCTAssertTrue(tracker.isConfirmed(for: .off))
    }
}
