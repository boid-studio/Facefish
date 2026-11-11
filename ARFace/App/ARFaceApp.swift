import SwiftUI
import Observation
import UIKit
import simd

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
                        case .stare: AvatarSession.shared.pendingMoves.append(.stare)
                        case .shush: AvatarSession.shared.pendingMoves.append(.shush)
                        case .sealed: AvatarSession.shared.pendingMoves.append(.sealed)
                        case .hide: AvatarSession.shared.pendingMoves.append(.hide)
                        case .show: AvatarSession.shared.pendingMoves.append(.show)
                        }
                    }
                    BluetoothControl.shared.stateProvider = {
                        let session = AvatarSession.shared
                        return MainAppState(
                            scene: session.avatarDebug.sceneSettings,
                            available: session.availableAccessories,
                            worn: Accessory.allCases.filter(session.wornAccessories.contains)
                        )
                    }
                    BluetoothControl.shared.onSetting = { setting in
                        let calibration = FaceCalibration.shared
                        // Scene changes from the control app are saved here by themselves.
                        if setting.isScene { AvatarSession.shared.avatarDebug.saveSceneSoon() }
                        switch setting {
                        case .centerFace: calibration.beginCapture()
                        case .mirror(let on): AvatarSession.shared.mirrored = on
                        case .phoneOrientation(let orientation): AvatarSession.shared.tracker.phoneOrientation = orientation
                        case .externalDisplayUpsideDown(let on): AvatarSession.shared.externalDisplayUpsideDown = on
                        case .faceCalibration(let on): calibration.enabled = on
                        case .lipSeal(let v): calibration.lipSeal = min(max(v, 0), 1)
                        case .puckerPriority(let v): calibration.puckerPriority = min(max(v, 0), 1)
                        case .gazeCorrection(let v): calibration.gazeCorrection = min(max(v, 0), 1)
                        case .cameraZ(let v): AvatarSession.shared.avatarDebug.cameraZ = min(max(v, 0.1), 3)
                        case .acting(let v): AvatarSession.shared.avatarDebug.acting = min(max(v, 0), 1)
                        case .waterColor(let color):
                            AvatarSession.shared.avatarDebug.waterColor = simd_clamp(color, .zero, .one)
                        case .whiteBalance(let v): AvatarSession.shared.avatarDebug.whiteBalance = min(max(v, -1), 1)
                        case .fieldOfView(let v): AvatarSession.shared.avatarDebug.fieldOfView = min(max(v, 15), 90)
                        case .vignette(let v): AvatarSession.shared.avatarDebug.vignette = min(max(v, 0), 1)
                        case .vignetteSize(let v): AvatarSession.shared.avatarDebug.vignetteSize = min(max(v, 0), 1.5)
                        case .vignetteSoftness(let v): AvatarSession.shared.avatarDebug.vignetteSoftness = min(max(v, 0.05), 2.5)
                        case .waterBrightness(let v): AvatarSession.shared.avatarDebug.waterBrightness = min(max(v, 0), 1.3)
                        case .causticIntensity(let v): AvatarSession.shared.avatarDebug.causticIntensity = min(max(v, 0), 3)
                        case .motionReaction(let v): AvatarSession.shared.avatarDebug.motionReaction = min(max(v, 0), 2)
                        case .debrisAmount(let v): AvatarSession.shared.avatarDebug.debrisAmount = min(max(v, 0), 2)
                        case .waterMotion(let v): AvatarSession.shared.avatarDebug.waterMotion = min(max(v, 0), 2)
                        case .distortion(let v): AvatarSession.shared.avatarDebug.distortion = min(max(v, 0), 1)
                        case .underwaterTint(let v): AvatarSession.shared.avatarDebug.underwaterTint = min(max(v, 0), 1)
                        case .scene(let part, let on): AvatarSession.shared.avatarDebug[scene: part] = on
                        case .saveScene: AvatarSession.shared.avatarDebug.saveScene()
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
    /// What the fish is wearing (the hat button), kept between launches. An accessory new to this
    /// phone starts as it's worn by default (Accessory.wornByDefault).
    var wornAccessories: Set<Accessory> = AvatarSession.loadWornAccessories() {
        didSet {
            UserDefaults.standard.set(wornAccessories.map(\.rawValue).sorted(), forKey: "wornAccessories")
        }
    }

    private static func loadWornAccessories() -> Set<Accessory> {
        let defaults = UserDefaults.standard
        var worn = Set((defaults.stringArray(forKey: "wornAccessories") ?? []).compactMap(Accessory.init(rawValue:)))
        let known = Set(defaults.stringArray(forKey: "knownAccessories") ?? [])
        for accessory in Accessory.allCases where !known.contains(accessory.rawValue) && accessory.wornByDefault {
            worn.insert(accessory)
        }
        defaults.set(Accessory.allCases.map(\.rawValue), forKey: "knownAccessories")
        defaults.set(worn.map(\.rawValue).sorted(), forKey: "wornAccessories")
        return worn
    }
    /// The accessories the loaded fish model has (AvatarController).
    var availableAccessories: [Accessory] = []
    var externalDisplayScene: UIWindowScene?
}

/// The fish's moves: a lap around the bowl (SwimAround); a quick spin, a vertical loop, a blush
/// behind its fins and blowing bubbles (SwimTrick).
enum SwimMove: CaseIterable {
    case lap, spin, loop, blush, bubbles
    /// Up to the lens, staring into it with her right eye (Stare).
    case stare
    /// A fin "finger" to her lips; zipping her lips shut (SwimTrick).
    case shush, sealed
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
