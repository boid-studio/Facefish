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
                // Poll independently of AR frames: orientation must work without a tracked face.
                TimelineView(.animation(minimumInterval: 0.1, paused: scenePhase != .active)) { _ in
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
                            .environment(\.colorScheme, .dark)   // light text on the black
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
                        // Below the Dynamic Island (the canvas ignores the safe area).
                        if isAvatarReady { TrackingStatusBanner(tracker: tracker).padding(.top, screenInsets.top) }
                    }
                    .overlay(alignment: .bottom) {
                        if isAvatarReady { CenterFaceBanner().padding(.bottom, 32) }
                    }
                    .overlay(alignment: .topTrailing) {
                        if isAvatarReady, avatarSession.showDebug {
                            CameraDebugView(tracker: tracker).padding(.top, 48).padding(.trailing, 12)
                        }
                    }
                    .modifier(CanvasOrientationEffect(isUpsideDown: tracker.isPhoneUpsideDown))
                }
                // Outside the polling timeline, so it isn't rebuilt under your finger.
                .overlay { ActionDrawer(isReady: isAvatarReady, settingsOnly: avatarSession.externalDisplayScene != nil) }
                .inspector(isPresented: $avatarSession.showDebug) {
                    DebugInspector(onShowControl: { showBluetooth = true })
                }
            }
        }
        .background { ExternalDisplayAccessoryRegistrar().frame(width: 0, height: 0) }
        // Full screen on the main phone: no clock, signal or battery, and the home bar tucked away.
        .statusBarHidden(!bluetooth.isControlMode)
        .persistentSystemOverlays(bluetooth.isControlMode ? .automatic : .hidden)
        .sheet(isPresented: $showBluetooth) { BluetoothControlView(showsDone: true) }
        .onAppear {
            bluetooth.start()   // the control link, ready by itself in either mode
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
            } else if phase == .active {
                bluetooth.start()
                if !bluetooth.isControlMode { tracker.start() }
            }
        }
    }

    /// The screen's safe-area insets (the Dynamic Island on top), which the canvas ignores.
    private var screenInsets: UIEdgeInsets {
        let scene = UIApplication.shared.connectedScenes.first { $0.session.role == .windowApplication } as? UIWindowScene
        return scene?.keyWindow?.safeAreaInsets ?? .zero
    }
}

#Preview {
    ContentView()
}
