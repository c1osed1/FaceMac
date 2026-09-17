import CoreVideo
import Foundation
import Vision

/// A similarity transform (uniform scale + rotation + translation):
/// `q = [[a, -b], [b, a]] * p + t`.
public struct SimilarityTransform: Equatable {
    public var a: Double
    public var b: Double
    public var tx: Double
    public var ty: Double

    public init(a: Double, b: Double, tx: Double, ty: Double) {
        self.a = a
        self.b = b
        self.tx = tx
        self.ty = ty
    }

    public func apply(_ point: CGPoint) -> CGPoint {
        CGPoint(
            x: a * Double(point.x) - b * Double(point.y) + tx,
            y: b * Double(point.x) + a * Double(point.y) + ty
        )
    }

    public var inverted: SimilarityTransform? {
        let scale = a * a + b * b
        guard scale > 0 else { return nil }
        let ia = a / scale
        let ib = -b / scale
        return SimilarityTransform(
            a: ia,
            b: ib,
            tx: -(ia * tx - ib * ty),
            ty: -(ib * tx + ia * ty)
        )
    }
}

/// Crops and aligns a face to the 112x112 ArcFace/SFace reference frame.
///
/// Recognition models such as SFace expect a similarity-aligned crop built from
/// five landmarks (eyes, nose, mouth corners), not a raw bounding-box crop.
public struct FaceAligner {
    public static let outputSize = 112

    /// ArcFace/SFace 112x112 template, ordered image-left to image-right:
    /// left eye, right eye, nose, left mouth corner, right mouth corner.
    public static let referenceTemplate: [CGPoint] = [
        CGPoint(x: 38.2946, y: 51.6963),
        CGPoint(x: 73.5318, y: 51.5014),
        CGPoint(x: 56.0252, y: 71.7366),
        CGPoint(x: 41.5493, y: 92.3655),
        CGPoint(x: 70.7299, y: 92.2041),
    ]

    public init() {}

    /// Five alignment points in image pixels, origin top-left.
    public func alignmentPoints(for face: DetectedFace, imageSize: CGSize) -> [CGPoint]? {
        guard let landmarks = face.landmarks else { return nil }

        func regionCenter(_ region: VNFaceLandmarkRegion2D?) -> CGPoint? {
            guard let region, region.pointCount > 0 else { return nil }
            let points = region.pointsInImage(imageSize: imageSize)
            var sum = CGPoint.zero
            for point in points {
                sum.x += point.x
                sum.y += point.y
            }
            let count = CGFloat(points.count)
            return Self.flipToTopLeft(CGPoint(x: sum.x / count, y: sum.y / count), imageSize: imageSize)
        }

        guard
            let leftEye = regionCenter(landmarks.leftEye),
            let rightEye = regionCenter(landmarks.rightEye),
            let nose = regionCenter(landmarks.nose),
            let outerLips = landmarks.outerLips,
            outerLips.pointCount >= 2
        else {
            return nil
        }

        let lipPoints = outerLips.pointsInImage(imageSize: imageSize)
            .map { Self.flipToTopLeft($0, imageSize: imageSize) }
        guard
            let mouthLeft = lipPoints.min(by: { $0.x < $1.x }),
            let mouthRight = lipPoints.max(by: { $0.x < $1.x })
        else {
            return nil
        }

        // Order strictly by x so the mapping matches the template regardless of
        // Vision's semantic left/right labelling.
        let eyes = [leftEye, rightEye].sorted { $0.x < $1.x }
        let mouth = [mouthLeft, mouthRight].sorted { $0.x < $1.x }
        return [eyes[0], eyes[1], nose, mouth[0], mouth[1]]
    }

    /// Aligns the face into a 112x112 BGRA pixel buffer, ready for CoreML.
    public func alignedCrop(from pixelBuffer: CVPixelBuffer, face: DetectedFace) -> CVPixelBuffer? {
        let imageSize = CGSize(
            width: CVPixelBufferGetWidth(pixelBuffer),
            height: CVPixelBufferGetHeight(pixelBuffer)
        )
        guard imageSize.width > 0, imageSize.height > 0 else { return nil }
        guard
            let points = alignmentPoints(for: face, imageSize: imageSize),
            let transform = Self.estimateSimilarity(from: points, to: Self.referenceTemplate)
        else {
            return nil
        }
        return Self.warp(pixelBuffer, transform: transform, size: Self.outputSize)
    }

    /// Least-squares similarity fit from `source` to `destination`.
    public static func estimateSimilarity(from source: [CGPoint], to destination: [CGPoint]) -> SimilarityTransform? {
        guard source.count == destination.count, source.count >= 2 else { return nil }

        let count = Double(source.count)
        let sourceMean = source.reduce(CGPoint.zero) { CGPoint(x: $0.x + $1.x, y: $0.y + $1.y) }
        let destinationMean = destination.reduce(CGPoint.zero) { CGPoint(x: $0.x + $1.x, y: $0.y + $1.y) }
        let sm = CGPoint(x: sourceMean.x / count, y: sourceMean.y / count)
        let dm = CGPoint(x: destinationMean.x / count, y: destinationMean.y / count)

        var energy = 0.0
        var dot = 0.0
        var cross = 0.0
        for index in 0..<source.count {
            let px = Double(source[index].x - sm.x)
            let py = Double(source[index].y - sm.y)
            let qx = Double(destination[index].x - dm.x)
            let qy = Double(destination[index].y - dm.y)
            energy += px * px + py * py
            dot += px * qx + py * qy
            cross += px * qy - py * qx
        }
        guard energy > 0 else { return nil }

        let a = dot / energy
        let b = cross / energy
        let tx = Double(dm.x) - (a * Double(sm.x) - b * Double(sm.y))
        let ty = Double(dm.y) - (b * Double(sm.x) + a * Double(sm.y))
        return SimilarityTransform(a: a, b: b, tx: tx, ty: ty)
    }

    // MARK: - Warp

    static func warp(_ pixelBuffer: CVPixelBuffer, transform: SimilarityTransform, size: Int) -> CVPixelBuffer? {
        guard let inverse = transform.inverted else { return nil }

        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        guard
            let sourceBase = CVPixelBufferGetBaseAddress(pixelBuffer),
            CVPixelBufferGetPixelFormatType(pixelBuffer) == kCVPixelFormatType_32BGRA
        else {
            return nil
        }
        let sourceWidth = CVPixelBufferGetWidth(pixelBuffer)
        let sourceHeight = CVPixelBufferGetHeight(pixelBuffer)
        let sourceStride = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let source = sourceBase.assumingMemoryBound(to: UInt8.self)

        var output: CVPixelBuffer?
        let attributes: [String: Any] = [
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
        ]
        guard CVPixelBufferCreate(
            kCFAllocatorDefault,
            size,
            size,
            kCVPixelFormatType_32BGRA,
            attributes as CFDictionary,
            &output
        ) == kCVReturnSuccess, let destination = output else {
            return nil
        }

        CVPixelBufferLockBaseAddress(destination, [])
        defer { CVPixelBufferUnlockBaseAddress(destination, []) }
        guard let destinationBase = CVPixelBufferGetBaseAddress(destination) else { return nil }
        let destinationStride = CVPixelBufferGetBytesPerRow(destination)
        let out = destinationBase.assumingMemoryBound(to: UInt8.self)

        for y in 0..<size {
            for x in 0..<size {
                let sourcePoint = inverse.apply(CGPoint(x: Double(x), y: Double(y)))
                let pixel = sampleBilinear(
                    source: source,
                    width: sourceWidth,
                    height: sourceHeight,
                    stride: sourceStride,
                    x: sourcePoint.x,
                    y: sourcePoint.y
                )
                let offset = y * destinationStride + x * 4
                out[offset + 0] = pixel.b
                out[offset + 1] = pixel.g
                out[offset + 2] = pixel.r
                out[offset + 3] = 255
            }
        }

        return destination
    }

    private struct RGB {
        let r: UInt8
        let g: UInt8
        let b: UInt8
    }

    private static func sampleBilinear(
        source: UnsafePointer<UInt8>,
        width: Int,
        height: Int,
        stride: Int,
        x: Double,
        y: Double
    ) -> RGB {
        let clampedX = min(max(x, 0), Double(width - 1))
        let clampedY = min(max(y, 0), Double(height - 1))
        let x0 = Int(clampedX.rounded(.down))
        let y0 = Int(clampedY.rounded(.down))
        let x1 = min(x0 + 1, width - 1)
        let y1 = min(y0 + 1, height - 1)
        let fx = clampedX - Double(x0)
        let fy = clampedY - Double(y0)

        func channel(_ px: Int, _ py: Int, _ offset: Int) -> Double {
            Double(source[py * stride + px * 4 + offset])
        }

        func blend(_ offset: Int) -> UInt8 {
            let top = channel(x0, y0, offset) * (1 - fx) + channel(x1, y0, offset) * fx
            let bottom = channel(x0, y1, offset) * (1 - fx) + channel(x1, y1, offset) * fx
            let value = top * (1 - fy) + bottom * fy
            return UInt8(min(max(value.rounded(), 0), 255))
        }

        return RGB(r: blend(2), g: blend(1), b: blend(0))
    }

    private static func flipToTopLeft(_ point: CGPoint, imageSize: CGSize) -> CGPoint {
        CGPoint(x: point.x, y: imageSize.height - point.y)
    }
}
