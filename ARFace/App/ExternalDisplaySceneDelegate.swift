import SwiftUI
import UIKit

final class ExternalDisplaySceneDelegate: NSObject, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let windowScene = scene as? UIWindowScene else { return }

        Self.selectPreferredSquareMode(on: windowScene.screen)

        let window = UIWindow(windowScene: windowScene)
        window.backgroundColor = .black
        window.rootViewController = UIHostingController(rootView: ExternalCanvasView())
        self.window = window
        window.isHidden = false
        AvatarSession.shared.externalDisplayScene = windowScene
    }

    func sceneDidDisconnect(_ scene: UIScene) {
        if AvatarSession.shared.externalDisplayScene === scene {
            AvatarSession.shared.externalDisplayScene = nil
        }
        window = nil
    }

    /// Picks 1080x1080 if offered, otherwise the square mode closest to it; leaves the mode unchanged if none are square.
    static func selectPreferredSquareMode(on screen: UIScreen) {
        let squareModes = screen.availableModes.filter { $0.size.width == $0.size.height }
        guard let best = squareModes.min(by: { abs($0.size.width - 1080) < abs($1.size.width - 1080) }) else { return }
        if screen.currentMode != best {
            screen.currentMode = best
        }
    }
}

private struct ExternalCanvasView: View {
    @State private var avatarSession = AvatarSession.shared
    @State private var bluetooth = BluetoothControl.shared
    @State private var isAvatarReady = false

    var body: some View {
        GeometryReader { geometry in
            let side = max(min(geometry.size.width, geometry.size.height), 1)

            Group {
                if bluetooth.isControlMode {
                    Text("Control mode")
                        .foregroundStyle(.white)
                } else {
                    AvatarView(
                        tracker: avatarSession.tracker,
                        mirrored: avatarSession.mirrored,
                        isReady: $isAvatarReady,
                        showsLoadError: false
                    )
                    .frame(width: side, height: side)
                    .clipped()
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .ignoresSafeArea()
        .background(.black)
        .persistentSystemOverlays(.hidden)
    }
}
