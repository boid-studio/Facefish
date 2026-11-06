import SwiftUI

struct BluetoothControlView: View {
    @State private var bluetooth = BluetoothControl.shared
    @Environment(\.dismiss) private var dismiss
    var showsDone = false

    var body: some View {
        NavigationStack {
            Form {
                Section("App mode") {
                    Toggle("Control mode", isOn: Binding(
                        get: { bluetooth.isControlMode },
                        set: { bluetooth.setControlMode($0) }
                    ))
                    Text(bluetooth.isControlMode
                         ? "This app sends commands to a main app. Face tracking is paused."
                         : "This is the main app. It works independently, even without a controller.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Connection") {
                    Text(bluetooth.status)
                        .accessibilityIdentifier("bluetoothStatus")
                    if bluetooth.isControlMode {
                        if bluetooth.rememberedMainApp != nil {
                            Button("Forget main app", role: .destructive) { bluetooth.forgetMainApp() }
                            Text("It reconnects to the main app by itself, whenever both apps are open. Forget it to pair with another.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        } else {
                            if !bluetooth.isPairing, !bluetooth.isConnecting, !bluetooth.isConnected {
                                Button("Find main app") { bluetooth.start() }
                            }
                            Text("Open the main app, then select it here. The first time, accept the iOS Bluetooth pairing prompt on both phones (before the helmet goes on). After that they find each other by themselves.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        if !bluetooth.isPairing, !bluetooth.isConnected {
                            Button("Start") { bluetooth.start() }
                        }
                        Text("The control app connects by itself whenever this app is open; nothing to press here. The first time, accept the iOS Bluetooth pairing prompt.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    if bluetooth.isConnecting {
                        ProgressView("Connecting…")
                    }
                    ForEach(bluetooth.devices, id: \.identifier) { device in
                        Button {
                            bluetooth.connect(to: device)
                        } label: {
                            VStack(alignment: .leading) {
                                Text(device.name ?? "Facefish main app")
                                Text(String(device.identifier.uuidString.prefix(8)))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .disabled(bluetooth.isConnecting)
                    }
                }

                if bluetooth.isControlMode {
                    Section("Commands") {
                        ForEach([ControlCommand.ping, .mirrorOn, .mirrorOff]) { command in
                            Button(command.title) { bluetooth.send(command) }
                                .disabled(!bluetooth.isConnected || bluetooth.isSending)
                        }
                        Text("Ping adds a log entry; Mirror on/off changes the main app's avatar mirroring.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Section("Received commands") {
                        if bluetooth.receivedCommands.isEmpty {
                            Text("No commands received yet.")
                                .foregroundStyle(.secondary)
                        } else {
                            Button("Clear log", role: .destructive) { bluetooth.clearLog() }
                            ForEach(bluetooth.receivedCommands) { entry in
                                HStack {
                                    Text(entry.payload.title)
                                    Spacer()
                                    Text(entry.date, style: .time)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        Text("The latest 100 commands are kept for this launch.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle(bluetooth.isControlMode ? "Control app" : "Bluetooth control")
            .toolbar {
                if showsDone {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
            }
        }
    }
}
