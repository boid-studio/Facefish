import SwiftUI

struct TrackingDebugSection: View {
    let tracker: FaceTracker

    @AppStorage("debug.blendShapeCount") private var blendShapeCount = 12

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
