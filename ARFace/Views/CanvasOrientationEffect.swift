import SwiftUI

/// Rotate the finished canvas, including RealityKit's background and post-processing.
/// Independent of system orientation support and the display's physical mounting.
struct CanvasOrientationEffect: ViewModifier {
    let isUpsideDown: Bool

    func body(content: Content) -> some View {
        content
            .rotationEffect(.degrees(isUpsideDown ? 180 : 0))
            .ignoresSafeArea()
    }
}
