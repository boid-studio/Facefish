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
                BluetoothControlView()
            } else if tracker.isSupported {
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
                    .overlay(alignment: .topTrailing) {
                        if isAvatarReady, avatarSession.showDebug {
                            CameraDebugView(tracker: tracker).padding(.top, 48).padding(.trailing, 12)
                        }
                    }
                    .overlay(alignment: .bottomTrailing) {
                        if isAvatarReady { settingsButton }
                    }
                    .inspector(isPresented: $avatarSession.showDebug) {
                        DebugInspector(onShowControl: { showBluetooth = true })
                    }
            } else {
                ContentUnavailableView(
                    "Face tracking unavailable",
                    systemImage: "faceid",
                    description: Text("This device needs a TrueDepth (Face ID) camera.")
                )
                .safeAreaInset(edge: .bottom) { bluetoothButton.padding() }
            }
        }
        .sheet(isPresented: $showBluetooth) { BluetoothControlView(showsDone: true) }
        .onAppear {
            tracker.setDebugEnabled(avatarSession.showDebug)
            if !bluetooth.isControlMode {
                tracker.start()
                if tracker.isSupported { avatarSession.audioMonitor.start() }
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
                if tracker.isSupported { avatarSession.audioMonitor.start() }
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

    private var bluetoothButton: some View {
        Button("Control", systemImage: "antenna.radiowaves.left.and.right") {
            showBluetooth = true
        }
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
