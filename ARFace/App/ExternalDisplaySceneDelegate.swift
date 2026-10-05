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
}

private struct ExternalCanvasView: View {
    @State private var avatarSession = AvatarSession.shared

    var body: some View {
        GeometryReader { geometry in
            let side = max(geometry.size.height, 1)

            AvatarView(
                tracker: avatarSession.tracker,
                mirrored: avatarSession.mirrored,
                showsLoadError: false
            )
            .frame(width: side, height: side)
            // Pre-stretch the square canvas to counter the square panel's HDMI squeeze.
            .scaleEffect(x: geometry.size.width / side, y: 1)
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
        }
        .ignoresSafeArea()
        .background(.black)
        .persistentSystemOverlays(.hidden)
    }
}
