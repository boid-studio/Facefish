import SwiftUI

struct TrackingDebugSection: View {
    let tracker: FaceTracker

    @AppStorage("debug.blendShapeCount") private var blendShapeCount = 12
    @Bindable private var calibration = FaceCalibration.shared

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { _ in
            LabeledContent("Status") {
                if let error = tracker.lastError {
                    Text(error).foregroundStyle(.red)
                } else if tracker.snapshot()?.isTracked == true {
                    Text("Tracking")
                } else {
                    Text("Looking for a face…").foregroundStyle(.secondary)
                }
            }
        }

        Button(calibration.isCapturing ? "Hold a relaxed face…" : "Center face") {
            calibration.beginCapture()
        }
        .disabled(calibration.isCapturing)
        Toggle("Face calibration", isOn: $calibration.enabled)
            .disabled(calibration.rest.isEmpty)
        if !calibration.rest.isEmpty {
            Button("Forget resting face", role: .destructive) { calibration.clear() }
        }
        LabeledContent("Lip seal") {
            Slider(value: $calibration.lipSeal, in: 0...1)
        }
        LabeledContent("Pucker priority") {
            Slider(value: $calibration.puckerPriority, in: 0...1)
        }

        Stepper("Top blend shapes: \(blendShapeCount)", value: $blendShapeCount, in: 4...52, step: 4)

        TimelineView(.periodic(from: .now, by: 0.1)) { _ in
            let top = (tracker.snapshot()?.blendShapes ?? [:])
                .sorted { $0.value > $1.value }
                .prefix(blendShapeCount)

            if top.isEmpty {
                Text("No face data")
                    .foregroundStyle(.secondary)
            } else {
                Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 4) {
                    ForEach(Array(top), id: \.key) { entry in
                        GridRow {
                            Text(BlendShapeMapping.displayName(entry.key))
                                .lineLimit(1)
                            ProgressView(value: Double(entry.value))
                            Text(entry.value, format: .number.precision(.fractionLength(2)))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .font(.caption.monospaced())
            }
        }
    }
}
