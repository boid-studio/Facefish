import SwiftUI

/// The control app's Accessories tab (the hat): what the fish wears, put on and taken off. The main
/// app is where it lives: on connecting this shows the accessories its fish model has and those
/// she's wearing, and each switch changes them there at once (it keeps them between launches).
struct AccessoriesControlView: View {
    @State private var bluetooth = BluetoothControl.shared
    /// What she's wearing, as the main app said on connecting and changed from here since.
    @State private var worn: Set<Accessory> = []

    /// The main app's model's accessories, or all known ones before it has said.
    private var available: [Accessory] {
        if let state = bluetooth.mainState, !state.available.isEmpty { return state.available }
        return Accessory.allCases
    }

    var body: some View {
        NavigationStack {
            Form {
                if !bluetooth.isConnected {
                    Label("Connect to a main app to dress the fish.", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.secondary)
                }
                Section {
                    ForEach(available) { accessory in
                        Toggle(accessory.title, systemImage: accessory.systemImage, isOn: Binding(
                            get: { worn.contains(accessory) },
                            set: { on in
                                if on { worn.insert(accessory) } else { worn.remove(accessory) }
                                bluetooth.send(.accessory(accessory, on))
                            }
                        ))
                    }
                } footer: {
                    Text("Switches show on the main app at once, and it keeps them. On connecting, this shows what she's wearing there.")
                }
            }
            .disabled(!bluetooth.isConnected)
            .navigationTitle("Accessories")
            .onChange(of: bluetooth.mainState?.worn) { _, worn in
                if let worn { self.worn = Set(worn) }
            }
            .onAppear {
                if let state = bluetooth.mainState { worn = Set(state.worn) }
            }
        }
    }
}
