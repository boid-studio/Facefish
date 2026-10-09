import SwiftUI

struct ContentView: View {
    @State private var avatarSession = AvatarSession.shared
    @State private var bluetooth = BluetoothControl.shared
    @State private var showBluetooth = false
    @State private var isAvatarReady = false
    @Environment(\.scenePhase) private var scenePhase
    private var tracker: FaceTracker { avatarSession.tracker }

    var body: some View {
        Group {
            if bluetooth.isControlMode {
                ControlTabView()
            } else {
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
                        AvatarView(
                            tracker: tracker,
                            mirrored: avatarSession.mirrored,
                            isReady: $isAvatarReady
                        )
                    }
                }
                    .ignoresSafeArea()
                    .overlay(alignment: .top) {
                        if isAvatarReady { TrackingStatusBanner(tracker: tracker) }
                    }
                    .overlay(alignment: .bottom) {
                        if isAvatarReady { CenterFaceBanner().padding(.bottom, 32) }
                    }
                    .overlay(alignment: .topTrailing) {
                        if isAvatarReady, avatarSession.showDebug {
                            CameraDebugView(tracker: tracker).padding(.top, 48).padding(.trailing, 12)
                        }
                    }
                    .overlay(alignment: .bottomTrailing) {
                        if isAvatarReady { settingsButton }
                    }
                    .overlay(alignment: .bottom) {
                        if isAvatarReady { moveButtons }
                    }
                    .inspector(isPresented: $avatarSession.showDebug) {
                        DebugInspector(onShowControl: { showBluetooth = true })
                    }
            }
        }
        .sheet(isPresented: $showBluetooth) { BluetoothControlView(showsDone: true) }
        .onAppear {
            tracker.setDebugEnabled(avatarSession.showDebug)
            if !bluetooth.isControlMode {
                tracker.start()
                avatarSession.audioMonitor.start()
            }
        }
        .onDisappear {
            tracker.stop()
            avatarSession.audioMonitor.stop()
        }
        .onChange(of: avatarSession.showDebug) { _, enabled in tracker.setDebugEnabled(enabled) }
        .onChange(of: bluetooth.isControlMode) { _, isControlMode in
            if isControlMode {
                showBluetooth = false
                avatarSession.showDebug = false
                tracker.stop()
                avatarSession.audioMonitor.stop()
            } else if scenePhase == .active {
                tracker.start()
                avatarSession.audioMonitor.start()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background {
                bluetooth.stop()
                tracker.stop()
            } else if phase == .active, !bluetooth.isControlMode {
                tracker.start()
            }
        }
    }

    /// Makes the fish swim a lap, spin, loop or blush (later also from the companion).
    private var moveButtons: some View {
        HStack(spacing: 16) {
            moveButton(.lap, systemImage: "point.forward.to.point.capsulepath", label: "Swim a lap")
            moveButton(.spin, systemImage: "rotate.3d", label: "Spin")
            moveButton(.loop, systemImage: "arrow.clockwise", label: "Loop")
            moveButton(.blush, systemImage: "heart", label: "Blush")
            moveButton(.bubbles, systemImage: "bubbles.and.sparkles", label: "Blow bubbles")
        }
        .padding(.bottom, 24)
    }

    private func moveButton(_ move: SwimMove, systemImage: String, label: String) -> some View {
        Button {
            avatarSession.pendingMoves.append(move)
        } label: {
            Image(systemName: systemImage)
                .font(.title3)
                .frame(width: 44, height: 44)
                .background(.ultraThinMaterial, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private var settingsButton: some View {
        Button {
            avatarSession.showDebug.toggle()
        } label: {
            Image(systemName: "slider.horizontal.3")
                .font(.title3)
                .frame(width: 44, height: 44)
                .background(.ultraThinMaterial, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Settings")
        .padding(.bottom, 24)
        .padding(.trailing, 16)
    }
}

#Preview {
    ContentView()
}
