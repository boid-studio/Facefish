import SwiftUI
import Observation
import UIKit

@main
struct ARFaceApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .onAppear {
                    BluetoothControl.shared.onCommand = { command in
                        switch command {
                        case .ping: break
                        case .mirrorOn: AvatarSession.shared.mirrored = true
                        case .mirrorOff: AvatarSession.shared.mirrored = false
                        }
                    }
                    BluetoothControl.shared.onSetting = { setting in
                        let calibration = FaceCalibration.shared
                        switch setting {
                        case .centerFace: calibration.beginCapture()
                        case .mirror(let on): AvatarSession.shared.mirrored = on
                        case .faceCalibration(let on): calibration.enabled = on
                        case .lipSeal(let v): calibration.lipSeal = min(max(v, 0), 1)
                        case .puckerPriority(let v): calibration.puckerPriority = min(max(v, 0), 1)
                        case .cameraZ(let v): AvatarSession.shared.avatarDebug.cameraZ = min(max(v, 0.1), 3)
                        }
                    }
                }
        }
    }
}

@Observable
final class AvatarSession {
    static let shared = AvatarSession()

    let tracker = FaceTracker()
    let audioMonitor = AudioLevelMonitor()
    let avatarDebug = AvatarDebugModel()
    var mirrored = true
    var showDebug = false
    /// Moves asked for (the buttons, later the companion), taken by the avatar in
    /// order; asks while a move is running are dropped.
    var pendingMoves: [SwimMove] = []
    var externalDisplayScene: UIWindowScene?
}

/// The fish's moves: a lap around the bowl (SwimAround); a quick spin, a vertical loop and a blush
/// behind its fins (SwimTrick).
enum SwimMove: CaseIterable {
    case lap, spin, loop, blush
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(
            name: nil,
            sessionRole: connectingSceneSession.role
        )
        if connectingSceneSession.role == .windowExternalDisplayNonInteractive {
            configuration.delegateClass = ExternalDisplaySceneDelegate.self
        }
        return configuration
    }
}
