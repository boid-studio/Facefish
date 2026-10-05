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
    }

    func sceneDidDisconnect(_ scene: UIScene) {
        window = nil
    }
}

private struct ExternalCanvasView: View {
    @State private var avatarSession = AvatarSession.shared

    var body: some View {
        AvatarView(
            tracker: avatarSession.tracker,
            mirrored: avatarSession.mirrored,
            showDebug: false,
            showsLoadError: false
        )
        .ignoresSafeArea()
        .background(.black)
        .persistentSystemOverlays(.hidden)
    }
}