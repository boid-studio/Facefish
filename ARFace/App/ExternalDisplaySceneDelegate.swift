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
                showDebug: false,
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

struct ExternalDisplayDebugView: View {
    let windowScene: UIWindowScene

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            let screen = windowScene.screen
            let sceneSize = windowScene.coordinateSpace.bounds.size

            VStack(alignment: .leading, spacing: 4) {
                Text("External display (iOS-reported)")
                    .font(.headline)
                Text("Screen: \(dimensions(screen.bounds.size)) pt")
                Text("Scene: \(dimensions(sceneSize)) pt")
                Text("Square canvas: \(dimensions(CGSize(width: sceneSize.height, height: sceneSize.height))) pt")
                Text("Horizontal pre-stretch: \(sceneSize.width / max(sceneSize.height, 1), specifier: "%.3f")x")
                Text("Native: \(dimensions(screen.nativeBounds.size)) px")
                Text("Native aspect (W/H): \(aspectRatio(screen.nativeBounds.size))")
                Text("Scale: \(screen.scale, format: .number.precision(.fractionLength(2)))")
                Text("Native scale: \(screen.nativeScale, format: .number.precision(.fractionLength(2)))")
                Text("Maximum refresh: \(screen.maximumFramesPerSecond) Hz")
                Text("Current mode: \(screen.currentMode.map { dimensions($0.size) + " px" } ?? "Unavailable")")
                Text("Preferred mode: \(screen.preferredMode.map { dimensions($0.size) + " px" } ?? "Unavailable")")
                Text("Available modes: \(screen.availableModes.map { dimensions($0.size) }.joined(separator: ", ")) px")
                Text("Overscan: \(overscanDescription(screen.overscanCompensation))")
                Text("Overscan insets (pt): T \(screen.overscanCompensationInsets.top, specifier: "%.1f"), L \(screen.overscanCompensationInsets.left, specifier: "%.1f"), B \(screen.overscanCompensationInsets.bottom, specifier: "%.1f"), R \(screen.overscanCompensationInsets.right, specifier: "%.1f")")
                Text("Panel stretching/cropping is not reported by iOS.")
                    .foregroundStyle(.secondary)
            }
            .font(.caption.monospaced())
            .padding(10)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private func dimensions(_ size: CGSize) -> String {
        String(format: "%.0f x %.0f", size.width, size.height)
    }

    private func aspectRatio(_ size: CGSize) -> String {
        guard size.height > 0 else { return "Unavailable" }
        return String(format: "%.3f:1", size.width / size.height)
    }

    private func overscanDescription(_ compensation: UIScreen.OverscanCompensation) -> String {
        switch compensation {
        case .scale: return "Scale"
        case .insetBounds: return "Inset bounds"
        case .none: return "None"
        @unknown default: return "Unknown (\(compensation.rawValue))"
        }
    }
}