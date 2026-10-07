import SwiftUI

struct AudioDebugSection: View {
    let monitor: AudioLevelMonitor

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.1)) { _ in
            let levels = monitor.snapshot()
            VStack(alignment: .leading, spacing: 6) {
                LabeledContent("Microphone", value: statusText)
                meter("Overall", value: levels.overall)
                meter("Low (20–250 Hz)", value: levels.low, threshold: AvatarController.audioBigBubbleLowThreshold)
                meter("Mid (250–2k Hz)", value: levels.mid)
                meter("High (2k–10k Hz)", value: levels.high, threshold: AvatarController.audioSmallBubbleHighThreshold)
            }
            .monospacedDigit()
        }
    }

    private var statusText: String {
        switch monitor.status {
        case .stopped: "Stopped"
        case .requestingPermission: "Requesting access"
        case .running: "Listening"
        case .denied: "Access denied"
        case .failed(let message): "Failed: \(message)"
        }
    }

    private func meter(_ title: String, value: Float, threshold: Float? = nil) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            LabeledContent(title) {
                Text(value, format: .number.precision(.fractionLength(2)))
            }
            ProgressView(value: Double(value))
                .tint(threshold.map { value > $0 } == true ? Color.orange : Color.accentColor)
        }
    }
}
