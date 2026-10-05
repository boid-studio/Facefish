import ARKit
import Synchronization
import UIKit

final class FaceTracker {
    let isSupported = ARFaceTrackingConfiguration.isSupported

    private let session = ARSession()
    private let receiver = FaceSessionReceiver()
    private let delegateQueue = DispatchQueue(label: "ARFace.FaceTracker", qos: .userInteractive)

    init() {
        session.delegate = receiver
        session.delegateQueue = delegateQueue
    }

    func start() {
        guard isSupported else { return }
        let configuration = ARFaceTrackingConfiguration()
        configuration.maximumNumberOfTrackedFaces = 1
        session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
        UIApplication.shared.isIdleTimerDisabled = true
    }

    func stop() {
        session.pause()
        receiver.latestFace.withLock { $0 = nil }
        receiver.cameraThumbnailData.withLock { $0 = nil }
        receiver.debugEnabled.withLock { $0 = false }
        UIApplication.shared.isIdleTimerDisabled = false
    }

    func setDebugEnabled(_ enabled: Bool) {
        receiver.debugEnabled.withLock { $0 = enabled }
        if !enabled {
            receiver.cameraThumbnailData.withLock { $0 = nil }
        }
    }

    /// Latest face state; safe to call every render frame.
    func snapshot() -> FaceState? {
        receiver.latestFace.withLock { $0 }
    }

    func cameraThumbnail() -> Data? {
        receiver.cameraThumbnailData.withLock { $0 }
    }

    var lastError: String? {
        receiver.lastError.withLock { $0 }
    }
}

nonisolated private final class FaceSessionReceiver: NSObject, ARSessionDelegate, Sendable {
    let latestFace = Mutex<FaceState?>(nil)
    let lastError = Mutex<String?>(nil)
    let debugEnabled = Mutex(false)
    let cameraThumbnailData = Mutex<Data?>(nil)
    private let lastThumbnailTimestamp = Mutex<TimeInterval>(-.infinity)
    private let imageContext = CIContext()

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        guard debugEnabled.withLock({ $0 }) else { return }

        let shouldCapture = lastThumbnailTimestamp.withLock { timestamp in
            guard frame.timestamp - timestamp >= 0.2 else { return false }
            timestamp = frame.timestamp
            return true
        }
        guard shouldCapture else { return }

        let cameraImage = CIImage(cvPixelBuffer: frame.capturedImage).oriented(.right)
        let scale = min(180 / cameraImage.extent.width, 240 / cameraImage.extent.height)
        let thumbnail = cameraImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        guard let cgImage = imageContext.createCGImage(thumbnail, from: thumbnail.extent),
              let data = UIImage(cgImage: cgImage).jpegData(compressionQuality: 0.55) else {
            return
        }
        cameraThumbnailData.withLock { $0 = data }
    }

    func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
        guard let face = anchors.lazy.compactMap({ $0 as? ARFaceAnchor }).first,
              let camera = session.currentFrame?.camera else { return }
        let cameraTransform = simd_inverse(camera.viewMatrix(for: .portrait))
        let state = FaceState(anchor: face, cameraTransform: cameraTransform)
        latestFace.withLock { $0 = state }
    }

    func session(_ session: ARSession, didRemove anchors: [ARAnchor]) {
        guard anchors.contains(where: { $0 is ARFaceAnchor }) else { return }
        latestFace.withLock { $0 = nil }
    }

    func session(_ session: ARSession, didFailWithError error: any Error) {
        let message = error.localizedDescription
        lastError.withLock { $0 = message }
    }
}
