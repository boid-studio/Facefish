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

                Section("Pairing") {
                    Text(bluetooth.status)
                        .accessibilityIdentifier("bluetoothStatus")
                    if bluetooth.isConnected || bluetooth.isPairing {
                        Button(bluetooth.isConnected ? "Disconnect" : "Cancel pairing", role: .destructive) {
                            bluetooth.stop()
                        }
                    } else {
                        Button(bluetooth.isControlMode ? "Find main app" : "Allow pairing") {
                            bluetooth.startPairing()
                        }
                    }
                    Text("Keep both apps open. Enable pairing on the main app, then find and select it on the control app. Accept the iOS Bluetooth pairing prompt if shown.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
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
                        ForEach(ControlCommand.allCases) { command in
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
                                    Text(entry.command.title)
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
