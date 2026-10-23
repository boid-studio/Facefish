import SwiftUI

/// Rotate the finished canvas, including RealityKit's background and post-processing.
/// Do not depend on UIKit supporting upside-down portrait on a particular device.
struct PhoneOrientationEffect: ViewModifier {
    let isUpsideDown: Bool

    func body(content: Content) -> some View {
        content
            .rotationEffect(.degrees(isUpsideDown ? 180 : 0))
            .ignoresSafeArea()
    }
}
