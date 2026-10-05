import SwiftUI
import UIKit

/// iOS-reported details of the connected external display.
struct ExternalDisplayDebugSection: View {
    let windowScene: UIWindowScene

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            let screen = windowScene.screen
            let sceneSize = windowScene.coordinateSpace.bounds.size

            group("Geometry") {
                LabeledContent("Screen", value: "\(dimensions(screen.bounds.size)) pt")
                LabeledContent("Scene", value: "\(dimensions(sceneSize)) pt")
                LabeledContent("Square canvas", value: "\(dimensions(CGSize(width: sceneSize.height, height: sceneSize.height))) pt")
                LabeledContent("Pre-stretch", value: String(format: "%.3fx", sceneSize.width / max(sceneSize.height, 1)))
                LabeledContent("Native", value: "\(dimensions(screen.nativeBounds.size)) px")
                LabeledContent("Native aspect", value: aspectRatio(screen.nativeBounds.size))
                LabeledContent("Scale", value: String(format: "%.2f (native %.2f)", screen.scale, screen.nativeScale))
            }
        }

        TimelineView(.periodic(from: .now, by: 1)) { _ in
            let screen = windowScene.screen

            group("Modes") {
                LabeledContent("Max refresh", value: "\(screen.maximumFramesPerSecond) Hz")
                LabeledContent("Current", value: screen.currentMode.map { dimensions($0.size) + " px" } ?? "Unavailable")
                LabeledContent("Preferred", value: screen.preferredMode.map { dimensions($0.size) + " px" } ?? "Unavailable")
                LabeledContent("Available") {
                    Text(screen.availableModes.map { dimensions($0.size) }.joined(separator: "\n"))
                        .multilineTextAlignment(.trailing)
                }
            }
        }

        TimelineView(.periodic(from: .now, by: 1)) { _ in
            let screen = windowScene.screen
            let insets = screen.overscanCompensationInsets

            group("Overscan") {
                LabeledContent("Compensation", value: overscanDescription(screen.overscanCompensation))
                LabeledContent("Insets (pt)", value: String(format: "T %.1f  L %.1f  B %.1f  R %.1f", insets.top, insets.left, insets.bottom, insets.right))
            }
        }

        Text("Panel stretching/cropping is not reported by iOS.")
            .font(.footnote)
            .foregroundStyle(.secondary)
    }

    private func group(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.subheadline.bold())
            content()
        }
        .font(.caption.monospacedDigit())
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
