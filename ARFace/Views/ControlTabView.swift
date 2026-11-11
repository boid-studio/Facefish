import SwiftUI

/// Root view of the control app: connection, quick actions and settings.
struct ControlTabView: View {
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        TabView {
            Tab("Connection", systemImage: "antenna.radiowaves.left.and.right") {
                BluetoothControlView().environment(\.horizontalSizeClass, sizeClass)
            }
            Tab("Actions", systemImage: "square.grid.2x2") {
                ControlActionsView().environment(\.horizontalSizeClass, sizeClass)
            }
            Tab("Scene", systemImage: "paintpalette") {
                SceneControlView().environment(\.horizontalSizeClass, sizeClass)
            }
            Tab("Accessories", systemImage: "hat.widebrim") {
                AccessoriesControlView().environment(\.horizontalSizeClass, sizeClass)
            }
            Tab("Settings", systemImage: "gearshape") {
                RemoteSettingsView().environment(\.horizontalSizeClass, sizeClass)
            }
        }
        // Compact size class keeps the tab bar at the bottom on iPad as well.
        .environment(\.horizontalSizeClass, .compact)
    }
}

/// Settings edited on the control app and pushed to the main app over Bluetooth.
/// Values are local mirrors that start at the main app's defaults; they aren't read back.
struct RemoteSettingsView: View {
    @State private var bluetooth = BluetoothControl.shared
    @AppStorage("remote.mirror") private var mirror = true
    @AppStorage("remote.phoneOrientation") private var phoneOrientation = PhoneOrientation.automatic
    @AppStorage("remote.externalDisplayUpsideDown") private var externalDisplayUpsideDown = false
    @AppStorage("remote.faceCalibration") private var faceCalibration = true
    @AppStorage("remote.lipSeal") private var lipSeal = 0.75
    @AppStorage("remote.puckerPriority") private var puckerPriority = 1.0
    @AppStorage("remote.gazeCorrection") private var gazeCorrection = 0.0
    @AppStorage("remote.acting") private var acting = 0.0
    @State private var centerFace = CenterFaceState.idle

    private enum CenterFaceState: Equatable {
        case idle, sending, capturing, done, failed
    }

    var body: some View {
        NavigationStack {
            Form {
                if !bluetooth.isConnected {
                    Label("Connect to a main app to change its settings.", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.secondary)
                }
                Section("General") {
                    Toggle("Mirror", systemImage: "arrow.left.and.right", isOn: $mirror)
                        .onChange(of: mirror) { _, v in bluetooth.send(.mirror(v)) }
                    Picker("Phone orientation", selection: $phoneOrientation) {
                        ForEach(PhoneOrientation.allCases) { orientation in
                            Text(orientation.title).tag(orientation)
                        }
                    }
                    .onChange(of: phoneOrientation) { _, v in bluetooth.send(.phoneOrientation(v)) }
                }
                Section {
                    Toggle("External display upside down", isOn: $externalDisplayUpsideDown)
                        .onChange(of: externalDisplayUpsideDown) { _, v in bluetooth.send(.externalDisplayUpsideDown(v)) }
                } header: {
                    Text("External display")
                } footer: {
                    Text("Rotates only the external image by 180 degrees. Independent of phone orientation; either or both can be upside down.")
                }
                Section {
                    centerFaceButton
                    Toggle("Face calibration", isOn: $faceCalibration)
                        .onChange(of: faceCalibration) { _, v in bluetooth.send(.faceCalibration(v)) }
                    slider("Lip seal", value: $lipSeal, in: 0...1) { .lipSeal(Float($0)) }
                    slider("Pucker priority", value: $puckerPriority, in: 0...1) { .puckerPriority(Float($0)) }
                    slider("Gaze correction", value: $gazeCorrection, in: 0...1) { .gazeCorrection(Float($0)) }
                } header: {
                    Text("Tracking")
                } footer: {
                    Text("Center face records the performer's relaxed face for 1.5 s on the main app. Gaze correction: how far down the performer looks (at a monitor under the camera) for the fish to look straight out.")
                }
                Section {
                    slider("Acting", value: $acting, in: 0...1) { .acting(Float($0)) }
                } header: {
                    Text("Performance")
                } footer: {
                    Text("0 follows the face as it is. Higher plays it bigger: stronger expressions and head moves, harder fins, and big notes that open the fins wide.")
                }
                Section {
                    Button("Send all settings") { sendAll() }
                } footer: {
                    Text("Pushes every value above to the main app, e.g. after reconnecting.")
                }
            }
            .disabled(!bluetooth.isConnected)
            .navigationTitle("Settings")
        }
    }

    private var centerFaceButton: some View {
        Button {
            centerFace = .sending
            bluetooth.send(.centerFace) { delivered in
                guard delivered else {
                    centerFace = .failed
                    resetCenterFace(after: 3)
                    return
                }
                centerFace = .capturing
                Task {
                    try? await Task.sleep(for: .seconds(1.5))
                    guard centerFace == .capturing else { return }
                    centerFace = .done
                    resetCenterFace(after: 2)
                }
            }
        } label: {
            HStack {
                Label(centerFaceTitle, systemImage: centerFaceIcon)
                    .contentTransition(.symbolEffect(.replace))
                Spacer()
                if centerFace == .sending || centerFace == .capturing {
                    ProgressView()
                }
            }
        }
        .foregroundStyle(centerFace == .failed ? .red : centerFace == .done ? .green : .accentColor)
        .disabled(centerFace == .sending || centerFace == .capturing)
        .sensoryFeedback(trigger: centerFace) { _, new in
            switch new {
            case .capturing: .impact
            case .done: .success
            case .failed: .error
            default: nil
            }
        }
        .animation(.default, value: centerFace)
    }

    private var centerFaceTitle: String {
        switch centerFace {
        case .idle: "Center face"
        case .sending: "Sending…"
        case .capturing: "Capturing – hold a relaxed face…"
        case .done: "Face centered"
        case .failed: "Not delivered – try again"
        }
    }

    private var centerFaceIcon: String {
        switch centerFace {
        case .idle, .sending: "face.dashed"
        case .capturing: "viewfinder"
        case .done: "checkmark.circle.fill"
        case .failed: "exclamationmark.triangle.fill"
        }
    }

    private func resetCenterFace(after seconds: Double) {
        Task {
            try? await Task.sleep(for: .seconds(seconds))
            centerFace = .idle
        }
    }

    private func slider(
        _ title: String, value: Binding<Double>, in range: ClosedRange<Double>, unit: String = "",
        setting: @escaping (Double) -> RemoteSetting
    ) -> some View {
        VStack(alignment: .leading) {
            LabeledContent(title) {
                Text("\(value.wrappedValue, specifier: "%.2f")\(unit)").monospacedDigit()
            }
            Slider(value: value, in: range) { Text(title) }
                .onChange(of: value.wrappedValue) { _, v in bluetooth.send(setting(v)) }
        }
    }

    private func sendAll() {
        bluetooth.send(.mirror(mirror))
        bluetooth.send(.phoneOrientation(phoneOrientation))
        bluetooth.send(.externalDisplayUpsideDown(externalDisplayUpsideDown))
        bluetooth.send(.faceCalibration(faceCalibration))
        bluetooth.send(.lipSeal(Float(lipSeal)))
        bluetooth.send(.puckerPriority(Float(puckerPriority)))
        bluetooth.send(.gazeCorrection(Float(gazeCorrection)))
        bluetooth.send(.acting(Float(acting)))
    }
}

struct ControlActionsView: View {
    @State private var bluetooth = BluetoothControl.shared

    private struct Action: Identifiable {
        let title: String
        let systemImage: String
        let command: ControlCommand
        var id: String { command.id }
    }

    /// The actions in groups, three across, so they all fit on screen.
    private let groups: [(title: String, actions: [Action])] = [
        ("Swim", [
            Action(title: "Lap", systemImage: "point.forward.to.point.capsulepath", command: .swimLap),
            Action(title: "Spin", systemImage: "rotate.3d", command: .spin),
            Action(title: "Loop", systemImage: "arrow.clockwise", command: .loop),
        ]),
        ("Feelings", [
            Action(title: "Blush", systemImage: "heart", command: .blush),
            Action(title: "Laugh", systemImage: "face.smiling", command: .laugh),
            Action(title: "Fart", systemImage: "wind", command: .fart),
        ]),
        ("Gags", [
            Action(title: "Stare", systemImage: "eyes", command: .stare),
            Action(title: "Shush", systemImage: "hand.point.up", command: .shush),
            Action(title: "Bubbles", systemImage: "bubbles.and.sparkles", command: .blowBubbles),
        ]),
        ("Stage", [
            Action(title: "Hide", systemImage: "eye.slash", command: .hide),
            Action(title: "Show", systemImage: "eye", command: .show),
            Action(title: "Play dead", systemImage: "zzz", command: .playDead),
            Action(title: "Wake up", systemImage: "sun.max", command: .wakeUp),
        ]),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                if !bluetooth.isConnected {
                    Label("Not connected to a main app", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.secondary)
                        .padding(.top)
                }
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(groups, id: \.title) { group in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(group.title).font(.headline).foregroundStyle(.secondary)
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                                ForEach(group.actions) { action in
                                    Button { bluetooth.send(action.command) } label: {
                                        VStack(spacing: 6) {
                                            Image(systemName: action.systemImage).font(.system(size: 28))
                                            Text(action.title).font(.subheadline.bold()).lineLimit(1).minimumScaleFactor(0.7)
                                        }
                                        .frame(maxWidth: .infinity, minHeight: 84)
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .buttonBorderShape(.roundedRectangle(radius: 16))
                                    .disabled(!bluetooth.isConnected || bluetooth.isSending)
                                }
                            }
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Actions")
        }
    }
}
