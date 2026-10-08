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
    var externalDisplayScene: UIWindowScene?
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
