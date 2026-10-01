import SwiftUI

struct ContentView: View {
    @State private var tracker = FaceTracker()
    @State private var mirrored = true
    @State private var showDebug = false

    var body: some View {
        Group {
            if tracker.isSupported {
                AvatarView(tracker: tracker, mirrored: mirrored, showDebug: showDebug)
                    .ignoresSafeArea()
                    .overlay(alignment: .top) { TrackingStatusBanner(tracker: tracker) }
                    .overlay(alignment: .topLeading) {
                        if showDebug { BlendShapeDebugView(tracker: tracker).padding(.top, 48) }
                    }
                    .safeAreaInset(edge: .bottom) { controls }
            } else {
                ContentUnavailableView(
                    "Face tracking unavailable",
                    systemImage: "faceid",
                    description: Text("This device needs a TrueDepth (Face ID) camera.")
                )
            }
        }
        .onAppear { tracker.start() }
        .onDisappear { tracker.stop() }
    }

    private var controls: some View {
        HStack(spacing: 12) {
            Toggle("Mirror", systemImage: "arrow.left.and.right", isOn: $mirrored)
            Toggle("Debug", systemImage: "slider.horizontal.3", isOn: $showDebug)
        }
        .toggleStyle(.button)
        .padding(8)
        .background(.ultraThinMaterial, in: Capsule())
        .padding(.bottom, 8)
    }
}

#Preview {
    ContentView()
}
