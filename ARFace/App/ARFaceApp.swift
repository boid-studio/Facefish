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
                        case .swimLap: AvatarSession.shared.pendingMoves.append(.lap)
                        case .spin: AvatarSession.shared.pendingMoves.append(.spin)
                        case .loop: AvatarSession.shared.pendingMoves.append(.loop)
                        case .blush: AvatarSession.shared.pendingMoves.append(.blush)
                        case .blowBubbles: AvatarSession.shared.pendingMoves.append(.bubbles)
                        case .hide: AvatarSession.shared.pendingMoves.append(.hide)
                        case .show: AvatarSession.shared.pendingMoves.append(.show)
                        }
                    }
                    BluetoothControl.shared.onSetting = { setting in
                        let calibration = FaceCalibration.shared
                        switch setting {
                        case .centerFace: calibration.beginCapture()
                        case .mirror(let on): AvatarSession.shared.mirrored = on
                        case .phoneOrientation(let orientation): AvatarSession.shared.tracker.phoneOrientation = orientation
                        case .externalDisplayUpsideDown(let on): AvatarSession.shared.externalDisplayUpsideDown = on
                        case .faceCalibration(let on): calibration.enabled = on
                        case .lipSeal(let v): calibration.lipSeal = min(max(v, 0), 1)
                        case .puckerPriority(let v): calibration.puckerPriority = min(max(v, 0), 1)
                        case .cameraZ(let v): AvatarSession.shared.avatarDebug.cameraZ = min(max(v, 0.1), 3)
                        case .acting(let v): AvatarSession.shared.avatarDebug.acting = min(max(v, 0), 1)
                        case .accessory(let accessory, let on):
                            if on {
                                AvatarSession.shared.wornAccessories.insert(accessory)
                            } else {
                                AvatarSession.shared.wornAccessories.remove(accessory)
                            }
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
    var externalDisplayUpsideDown = UserDefaults.standard.bool(forKey: "externalDisplay.upsideDown") {
        didSet {
            UserDefaults.standard.set(externalDisplayUpsideDown, forKey: "externalDisplay.upsideDown")
        }
    }
    /// Moves asked for (the buttons, later the companion), taken by the avatar in
    /// order; asks while a move is running are dropped.
    var pendingMoves: [SwimMove] = []
    /// The fish is backing out of frame or out of sight (HideShow), for the Hide/Show button.
    var fishHidden = false
    /// What the fish is wearing (the hat button), kept between launches.
    var wornAccessories: Set<Accessory> = Set(
        (UserDefaults.standard.stringArray(forKey: "wornAccessories") ?? []).compactMap(Accessory.init(rawValue:))
    ) {
        didSet {
            UserDefaults.standard.set(wornAccessories.map(\.rawValue).sorted(), forKey: "wornAccessories")
        }
    }
    /// The accessories the loaded fish model has (AvatarController).
    var availableAccessories: [Accessory] = []
    var externalDisplayScene: UIWindowScene?
}

/// The fish's moves: a lap around the bowl (SwimAround); a quick spin, a vertical loop, a blush
/// behind its fins and blowing bubbles (SwimTrick).
enum SwimMove: CaseIterable {
    case lap, spin, loop, blush, bubbles
    /// Back out of frame and stay hidden, then swim back in (HideShow).
    case hide, show
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
        // Pre-iOS 27 path; on iOS 27+ the scene comes from ExternalDisplayAccessoryRegistrar.
        if connectingSceneSession.role == .windowExternalDisplayNonInteractive {
            configuration.delegateClass = ExternalDisplaySceneDelegate.self
        }
        return configuration
    }
}
