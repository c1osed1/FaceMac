import AVFoundation
import SwiftUI

/// Live camera preview backed by the shared capture session, mirrored like a
/// selfie so head movement matches what the user sees.
struct CameraPreview: NSViewRepresentable {
    let session: AVCaptureSession

    func makeNSView(context: Context) -> PreviewView {
        PreviewView(session: session)
    }

    func updateNSView(_ nsView: PreviewView, context: Context) {
        nsView.applyMirroring()
    }
}

final class PreviewView: NSView {
    private let previewLayer: AVCaptureVideoPreviewLayer
    private var startObserver: NSObjectProtocol?

    init(session: AVCaptureSession) {
        previewLayer = AVCaptureVideoPreviewLayer(session: session)
        super.init(frame: .zero)

        wantsLayer = true
        previewLayer.videoGravity = .resizeAspectFill
        previewLayer.frame = bounds
        previewLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        layer = previewLayer

        // The layer has no connection until the session actually runs, so
        // mirroring has to be applied again once it starts.
        startObserver = NotificationCenter.default.addObserver(
            forName: .AVCaptureSessionDidStartRunning,
            object: session,
            queue: .main
        ) { [weak self] _ in
            self?.applyMirroring()
        }
        applyMirroring()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    deinit {
        if let startObserver {
            NotificationCenter.default.removeObserver(startObserver)
        }
    }

    override func layout() {
        super.layout()
        previewLayer.frame = bounds
        applyMirroring()
    }

    func applyMirroring() {
        guard let connection = previewLayer.connection, connection.isVideoMirroringSupported else { return }
        connection.automaticallyAdjustsVideoMirroring = false
        connection.isVideoMirrored = true
    }
}
