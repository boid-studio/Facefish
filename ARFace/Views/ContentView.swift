import SwiftUI

struct ContentView: View {
    @State private var avatarSession = AvatarSession.shared
    @State private var showDebug = false

    private var tracker: FaceTracker { avatarSession.tracker }

    var body: some View {
        Group {
            if tracker.isSupported {
                AvatarView(tracker: tracker, mirrored: avatarSession.mirrored, showDebug: showDebug)
                    .ignoresSafeArea()
                    .overlay(alignment: .top) { TrackingStatusBanner(tracker: tracker) }
                    .overlay(alignment: .topLeading) {
                        if showDebug { BlendShapeDebugView(tracker: tracker).padding(.top, 48) }
                    }
                    .overlay(alignment: .topTrailing) {
                        if showDebug { CameraDebugView(tracker: tracker).padding(.top, 48).padding(.trailing, 12) }
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
        .onAppear {
            tracker.setDebugEnabled(showDebug)
            tracker.start()
        }
        .onDisappear { tracker.stop() }
        .onChange(of: showDebug) { _, enabled in tracker.setDebugEnabled(enabled) }
    }

    private var controls: some View {
        HStack(spacing: 12) {
            Toggle("Mirror", systemImage: "arrow.left.and.right", isOn: $avatarSession.mirrored)
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
