import SwiftUI

struct ContentView: View {
    @State private var avatarSession = AvatarSession.shared
    private var tracker: FaceTracker { avatarSession.tracker }

    var body: some View {
        Group {
            if tracker.isSupported {
                Group {
                    if avatarSession.externalDisplayScene != nil {
                        VStack(spacing: 12) {
                            Image(systemName: "display")
                                .font(.largeTitle)
                            Text("External display connected")
                                .font(.headline)
                            Text("Face tracking is active. The avatar is rendered only on the external display.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .padding(24)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(.black)
                    } else {
                        AvatarView(tracker: tracker, mirrored: avatarSession.mirrored)
                    }
                }
                    .ignoresSafeArea()
                    .overlay(alignment: .top) { TrackingStatusBanner(tracker: tracker) }
                    .overlay(alignment: .topTrailing) {
                        if avatarSession.showDebug { CameraDebugView(tracker: tracker).padding(.top, 48).padding(.trailing, 12) }
                    }
                    .safeAreaInset(edge: .bottom) { controls }
                    .inspector(isPresented: $avatarSession.showDebug) { DebugInspector() }
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
            if tracker.isSupported { avatarSession.audioMonitor.start() }
        }
        .onDisappear {
            tracker.stop()
            avatarSession.audioMonitor.stop()
        }
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
