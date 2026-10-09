import ARKit
import SwiftUI

struct TrackingStatusBanner: View {
    let tracker: FaceTracker

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { _ in
            if !tracker.isSupported {
                banner(Label("Face tracking unavailable", systemImage: "faceid"))
            } else if let error = tracker.lastError {
                banner(Label(error, systemImage: "exclamationmark.triangle"))
            } else if tracker.snapshot()?.isTracked != true {
                banner(Label("Looking for a face…", systemImage: "faceid"))
            }
        }
    }

    private func banner(_ label: some View) -> some View {
        label
            .font(.callout)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial, in: Capsule())
            .padding(.top, 8)
    }
}

struct CameraDebugView: View {
    let tracker: FaceTracker

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.2)) { _ in
            Group {
                if let data = tracker.cameraThumbnail(), let image = UIImage(data: data) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(systemName: "camera")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(.ultraThinMaterial)
                }
            }
            .frame(width: 120, height: 160)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(.white.opacity(0.35), lineWidth: 1)
            }
        }
    }
}

/// Shows progress and the result of a "Center face" capture, whether started locally or remotely.
struct CenterFaceBanner: View {
    private var calibration = FaceCalibration.shared

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
            Group {
                if calibration.isCapturing {
                    Label("Centering face – hold a relaxed face…", systemImage: "viewfinder")
                } else if let last = calibration.lastCapture,
                          context.date.timeIntervalSince(last.date) < 2.5 {
                    Label(last.succeeded ? "Face centered" : "Centering failed – no face found",
                          systemImage: last.succeeded ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(last.succeeded ? .green : .orange)
                }
            }
            .font(.headline)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial, in: Capsule())
            .transition(.opacity)
        }
        .animation(.default, value: calibration.isCapturing)
        .allowsHitTesting(false)
    }
}
