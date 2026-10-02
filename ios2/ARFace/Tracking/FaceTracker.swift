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
        UIApplication.shared.isIdleTimerDisabled = false
    }

    /// Latest face state; safe to call every render frame.
    func snapshot() -> FaceState? {
        receiver.latestFace.withLock { $0 }
    }

    var lastError: String? {
        receiver.lastError.withLock { $0 }
    }
}

nonisolated private final class FaceSessionReceiver: NSObject, ARSessionDelegate, Sendable {
    let latestFace = Mutex<FaceState?>(nil)
    let lastError = Mutex<String?>(nil)

    func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
        guard let face = anchors.lazy.compactMap({ $0 as? ARFaceAnchor }).first else { return }
        let state = FaceState(anchor: face)
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
