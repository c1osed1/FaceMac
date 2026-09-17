import AVFoundation
import CoreMedia
import CoreVideo
import Foundation

public protocol CameraCaptureDelegate: AnyObject {
    func cameraCapture(_ capture: CameraCapture, didOutput pixelBuffer: CVPixelBuffer, at time: CMTime)
}

/// Shared camera. A single `AVCaptureSession` is reused by the preview, the
/// enroller and the unlock coordinator — two sessions would fight over the
/// camera. Callers `acquire()` while they need frames and `relinquish()`
/// afterwards; the session stops when the last holder lets go.
public final class CameraCapture: NSObject {
    public static let shared = CameraCapture()

    public enum CaptureError: Error {
        case noCamera
        case cannotAddInput
        case cannotAddOutput
    }

    private final class WeakDelegate {
        weak var value: CameraCaptureDelegate?
        init(_ value: CameraCaptureDelegate) {
            self.value = value
        }
    }

    private let session = AVCaptureSession()
    private let output = AVCaptureVideoDataOutput()
    private let queue = DispatchQueue(label: "com.facemac.camera")
    private var delegates: [WeakDelegate] = []
    private var configured = false
    private var holders = 0

    public var previewSession: AVCaptureSession { session }
    public private(set) var isRunning = false

    public override init() {
        super.init()
    }

    // MARK: - Delegates

    public func addDelegate(_ delegate: CameraCaptureDelegate) {
        delegates.removeAll { $0.value == nil }
        guard !delegates.contains(where: { $0.value === delegate }) else { return }
        delegates.append(WeakDelegate(delegate))
    }

    public func removeDelegate(_ delegate: CameraCaptureDelegate) {
        delegates.removeAll { $0.value == nil || $0.value === delegate }
    }

    // MARK: - Lifecycle

    public func acquire() throws {
        holders += 1
        do {
            try startIfNeeded()
        } catch {
            holders -= 1
            throw error
        }
    }

    public func relinquish() {
        holders = max(0, holders - 1)
        if holders == 0 { stop() }
    }

    private func startIfNeeded() throws {
        if !configured { try configure() }
        guard !session.isRunning else { return }
        session.startRunning()
        isRunning = true
        Log.camera.info("camera started")
    }

    private func stop() {
        guard session.isRunning else { return }
        session.stopRunning()
        isRunning = false
        Log.camera.info("camera stopped")
    }

    private func configure() throws {
        session.beginConfiguration()
        session.sessionPreset = .vga640x480

        let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .unspecified)
            ?? AVCaptureDevice.default(for: .video)
        guard let device else {
            session.commitConfiguration()
            throw CaptureError.noCamera
        }

        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input) else {
            session.commitConfiguration()
            throw CaptureError.cannotAddInput
        }
        session.addInput(input)

        output.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)
        ]
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: queue)

        guard session.canAddOutput(output) else {
            session.commitConfiguration()
            throw CaptureError.cannotAddOutput
        }
        session.addOutput(output)

        session.commitConfiguration()
        configured = true
    }
}

extension CameraCapture: AVCaptureVideoDataOutputSampleBufferDelegate {
    public func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let time = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        for holder in delegates {
            holder.value?.cameraCapture(self, didOutput: pixelBuffer, at: time)
        }
    }
}
