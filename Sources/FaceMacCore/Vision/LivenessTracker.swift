import CoreGraphics
import Foundation
import Vision

/// How much proof of "a live person, not a photo" is required before the
/// password is typed.
public enum LivenessMode: String, CaseIterable, Codable, Sendable {
    case off
    case blink
    case motion
    case blinkOrMotion
    case blinkAndMotion

    public var requiresConfirmation: Bool { self != .off }

    public init(storedValue: String?) {
        self = LivenessMode(rawValue: storedValue ?? "") ?? .blinkOrMotion
    }
}

public struct LivenessConfiguration {
    /// Eye aspect ratio (contour height / width) below which the eyes are
    /// considered shut, and above which they are open again after a blink.
    public var blinkClosedRatio: Float = 0.20
    public var blinkOpenRatio: Float = 0.28
    /// Total landmark/head-pose movement (normalised units) that counts as
    /// natural micro-motion within `motionWindow`.
    public var motionThreshold: Float = 0.05
    public var motionWindow: TimeInterval = 1.5

    public init() {}
}

public struct LivenessSnapshot {
    public let eyeAspectRatio: Float?
    public let blinkDetected: Bool
    public let motion: Float
    public let isLive: Bool
}

/// Cheap, on-device liveness cues from the same Vision landmarks already used for
/// recognition: a blink (eye aspect ratio dip + recovery) and natural
/// micro-motion of landmarks and head pose.
///
/// Landmark positions are taken in face-normalised space, so simply moving or
/// scaling a printed photo does not register as motion — only a face that
/// actually changes shape/pose does.
public final class LivenessTracker {
    public private(set) var blinkDetected = false
    public private(set) var motionConfirmed = false
    public private(set) var lastEyeAspectRatio: Float?

    private let configuration: LivenessConfiguration

    private var eyesClosed = false
    private var previousSignature: [CGPoint]?
    private var previousPose: (yaw: Float, pitch: Float, roll: Float)?
    private var accumulatedMotion: Float = 0
    private var windowStartedAt: Date?

    public init(configuration: LivenessConfiguration = .init()) {
        self.configuration = configuration
    }

    public func reset() {
        blinkDetected = false
        motionConfirmed = false
        lastEyeAspectRatio = nil
        eyesClosed = false
        previousSignature = nil
        previousPose = nil
        accumulatedMotion = 0
        windowStartedAt = nil
    }

    public func isConfirmed(for mode: LivenessMode) -> Bool {
        Self.isLive(mode: mode, blink: blinkDetected, motion: motionConfirmed)
    }

    @discardableResult
    public func observe(face: DetectedFace, imageSize: CGSize, at time: Date = Date()) -> LivenessSnapshot {
        if let ratio = Self.eyeAspectRatio(face.landmarks, imageSize: imageSize) {
            lastEyeAspectRatio = ratio
            if ratio < configuration.blinkClosedRatio {
                eyesClosed = true
            } else if eyesClosed, ratio > configuration.blinkOpenRatio {
                blinkDetected = true
                eyesClosed = false
            }
        }

        let signature = Self.motionSignature(face.landmarks)
        if let previousSignature, previousSignature.count == signature.count {
            accumulatedMotion += Self.meanDisplacement(from: previousSignature, to: signature)
        }
        previousSignature = signature

        let pose = (face.yaw, face.pitch, face.roll)
        if let previousPose {
            accumulatedMotion += Self.poseDelta(from: previousPose, to: pose)
        }
        previousPose = pose

        if let windowStartedAt, time.timeIntervalSince(windowStartedAt) > configuration.motionWindow {
            accumulatedMotion = 0
            self.windowStartedAt = time
        }
        if windowStartedAt == nil { windowStartedAt = time }

        if accumulatedMotion >= configuration.motionThreshold {
            motionConfirmed = true
        }

        return LivenessSnapshot(
            eyeAspectRatio: lastEyeAspectRatio,
            blinkDetected: blinkDetected,
            motion: accumulatedMotion,
            isLive: blinkDetected || motionConfirmed
        )
    }

    // MARK: - Testable math

    static func isLive(mode: LivenessMode, blink: Bool, motion: Bool) -> Bool {
        switch mode {
        case .off: return true
        case .blink: return blink
        case .motion: return motion
        case .blinkOrMotion: return blink || motion
        case .blinkAndMotion: return blink && motion
        }
    }

    /// Eye aspect ratio, averaged over both visible eyes: the contour's
    /// height/width. Open eyes are wide and short; a blink collapses the height.
    static func eyeAspectRatio(_ landmarks: VNFaceLandmarks2D?, imageSize: CGSize) -> Float? {
        guard let landmarks else { return nil }
        var ratios: [Float] = []
        for region in [landmarks.leftEye, landmarks.rightEye] {
            guard let region, region.pointCount >= 4 else { continue }
            let points = region.pointsInImage(imageSize: imageSize)
            let xs = points.map(\.x)
            let ys = points.map(\.y)
            guard
                let minX = xs.min(), let maxX = xs.max(),
                let minY = ys.min(), let maxY = ys.max()
            else { continue }
            let width = maxX - minX
            let height = maxY - minY
            guard width > 0 else { continue }
            ratios.append(Float(height / width))
        }
        guard !ratios.isEmpty else { return nil }
        return ratios.reduce(0, +) / Float(ratios.count)
    }

    /// Centroids of a few landmark regions, normalised to the face bounding box,
    /// so the signature is invariant to the face moving or changing size.
    static func motionSignature(_ landmarks: VNFaceLandmarks2D?) -> [CGPoint] {
        guard let landmarks else { return [] }
        let regions: [VNFaceLandmarkRegion2D?] = [
            landmarks.nose,
            landmarks.leftEye,
            landmarks.rightEye,
            landmarks.outerLips,
        ]
        return regions.compactMap { region -> CGPoint? in
            guard let region, region.pointCount > 0 else { return nil }
            let points = region.normalizedPoints
            var sum = CGPoint.zero
            for index in 0..<region.pointCount {
                sum.x += points[index].x
                sum.y += points[index].y
            }
            let count = CGFloat(region.pointCount)
            return CGPoint(x: sum.x / count, y: sum.y / count)
        }
    }

    static func meanDisplacement(from source: [CGPoint], to destination: [CGPoint]) -> Float {
        guard source.count == destination.count, !source.isEmpty else { return 0 }
        var total: Float = 0
        for index in source.indices {
            let dx = Float(destination[index].x - source[index].x)
            let dy = Float(destination[index].y - source[index].y)
            total += (dx * dx + dy * dy).squareRoot()
        }
        return total / Float(source.count)
    }

    static func poseDelta(
        from previous: (yaw: Float, pitch: Float, roll: Float),
        to current: (yaw: Float, pitch: Float, roll: Float)
    ) -> Float {
        abs(current.yaw - previous.yaw)
            + abs(current.pitch - previous.pitch)
            + abs(current.roll - previous.roll)
    }
}
