import SwiftUI

struct ContentView: View {
    @State private var avatarSession = AvatarSession.shared
    private var tracker: FaceTracker { avatarSession.tracker }

    var body: some View {
        Group {
            if tracker.isSupported {
                AvatarView(tracker: tracker, mirrored: avatarSession.mirrored, showDebug: avatarSession.showDebug)
                    .ignoresSafeArea()
                    .overlay(alignment: .top) { TrackingStatusBanner(tracker: tracker) }
                    .overlay(alignment: .topLeading) {
                        if avatarSession.showDebug { BlendShapeDebugView(tracker: tracker).padding(.top, 48) }
                    }
                    .overlay(alignment: .topTrailing) {
                        if avatarSession.showDebug { CameraDebugView(tracker: tracker).padding(.top, 48).padding(.trailing, 12) }
                    }
                    .safeAreaInset(edge: .bottom) {
                        VStack(spacing: 8) {
                            if avatarSession.showDebug, let scene = avatarSession.externalDisplayScene {
                                ScrollView {
                                    ExternalDisplayDebugView(windowScene: scene)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .frame(maxHeight: 200)
                                .padding(.horizontal, 12)
                            }
                            controls
                        }
                    }
            } else {
                ContentUnavailableView(
                    "Face tracking unavailable",
                    systemImage: "faceid",
                    description: Text("This device needs a TrueDepth (Face ID) camera.")
                )
            }
        }
        .onAppear {
            tracker.setDebugEnabled(avatarSession.showDebug)
            tracker.start()
        }
        .onDisappear { tracker.stop() }
        .onChange(of: avatarSession.showDebug) { _, enabled in tracker.setDebugEnabled(enabled) }
    }

    private var controls: some View {
        HStack(spacing: 12) {
            Toggle("Mirror", systemImage: "arrow.left.and.right", isOn: $avatarSession.mirrored)
            Toggle("Debug", systemImage: "slider.horizontal.3", isOn: $avatarSession.showDebug)
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
