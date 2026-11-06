import SwiftUI
import simd

/// The control app's Scene tab: the look of the scene for a cosplay setup (the water's colour,
/// white balance, the camera) and the effects. The main app is where the scene lives: on connecting
/// this reads it from there, and changes show there right away and are saved there by themselves
/// (it loads them at launch).
struct SceneControlView: View {
    @State private var bluetooth = BluetoothControl.shared
    @Environment(\.self) private var environment
    /// Linear RGB, "r,g,b".
    @AppStorage("remote.scene.water") private var water = "0.02,0.26,0.44"
    @AppStorage("remote.scene.whiteBalance") private var whiteBalance = 0.0
    @AppStorage("remote.scene.fieldOfView") private var fieldOfView = 35.0
    @AppStorage("remote.scene.vignette") private var vignette = 0.0
    @AppStorage("remote.scene.vignetteSize2") private var vignetteSize = 0.6
    @AppStorage("remote.scene.vignetteSoftness") private var vignetteSoftness = 1.2
    @AppStorage("remote.scene.brightness") private var brightness = 1.0
    @AppStorage("remote.cameraZ") private var cameraZ = 0.75
    @AppStorage("remote.scene.causticIntensity") private var causticIntensity = 1.0
    @AppStorage("remote.scene.motionReaction") private var motionReaction = 1.0
    @AppStorage("remote.scene.debris") private var debrisAmount = 1.0
    @AppStorage("remote.scene.waterMotion") private var waterMotion = 1.0
    @AppStorage("remote.scene.distortion") private var distortion = 0.0
    /// The effects switched off, comma-separated SceneSwitch names.
    @AppStorage("remote.scene.off") private var switchedOff = ""

    var body: some View {
        NavigationStack {
            Form {
                if !bluetooth.isConnected {
                    Label("Connect to a main app to change its scene.", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.secondary)
                }
                Section {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 64), spacing: 12)], spacing: 12) {
                        ForEach(WaterPreset.allCases) { preset in
                            Button { setWater(preset.water) } label: {
                                VStack(spacing: 6) {
                                    Circle()
                                        .fill(Self.color(preset.water))
                                        .frame(width: 44, height: 44)
                                        .overlay {
                                            if simd_distance(preset.water, waterColor) < 0.004 {
                                                Circle().strokeBorder(.primary, lineWidth: 3)
                                            }
                                        }
                                    Text(preset.title).font(.caption)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                    ColorPicker("Custom colour", selection: Binding(
                        get: { Self.color(waterColor) },
                        set: { color in
                            let resolved = color.resolve(in: environment)
                            setWater(SIMD3(resolved.linearRed, resolved.linearGreen, resolved.linearBlue))
                        }
                    ), supportsOpacity: false)
                    slider("Background brightness", value: $brightness, in: 0...1.3, format: "%.2f", unit: "") {
                        .waterBrightness(Float($0))
                    }
                } header: {
                    Text("Water colour")
                } footer: {
                    Text("The whole sea follows: depth, light rays, the haze on the fish, the lights and specks. Background brightness 0 is black water, 1 as designed; the fish stays lit.")
                }

                Section {
                    VStack(alignment: .leading) {
                        LabeledContent("White balance") {
                            Text(whiteBalance == 0 ? "Neutral" : String(format: "%+.2f", whiteBalance)).monospacedDigit()
                        }
                        Slider(value: $whiteBalance, in: -1...1) {
                            Text("White balance")
                        } minimumValueLabel: {
                            Image(systemName: "thermometer.snowflake")
                        } maximumValueLabel: {
                            Image(systemName: "thermometer.sun")
                        }
                        .onChange(of: whiteBalance) { _, v in bluetooth.send(.whiteBalance(Float(v))) }
                    }
                    Button("Neutral") { whiteBalance = 0 }
                        .disabled(whiteBalance == 0)
                } header: {
                    Text("White balance")
                } footer: {
                    Text("Cooler (bluer) to the left, warmer (redder) to the right, on the whole image.")
                }

                Section {
                    slider("Amount", value: $vignette, in: 0...1, format: "%.2f", unit: "") {
                        .vignette(Float($0))
                    }
                    slider("Size", value: $vignetteSize, in: 0...1.5, format: "%.2f", unit: "") {
                        .vignetteSize(Float($0))
                    }
                    slider("Softness", value: $vignetteSoftness, in: 0.1...2.5, format: "%.2f", unit: "") {
                        .vignetteSoftness(Float($0))
                    }
                } header: {
                    Text("Vignette")
                } footer: {
                    Text("Darkens toward the edges in a circle: as wide as the screen in portrait, and the round display's own circle on it (its edge is size 1). 0 turns it off.")
                }

                Section("Camera") {
                    slider("Field of view", value: $fieldOfView, in: 20...70, format: "%.0f", unit: "°") {
                        .fieldOfView(Float($0))
                    }
                    slider("Zoom (camera distance)", value: $cameraZ, in: 0.1...3, format: "%.2f", unit: " m") {
                        .cameraZ(Float($0))
                    }
                }

                Section("Effects") {
                    ForEach(SceneSwitch.allCases) { part in
                        Toggle(part.title, isOn: Binding(
                            get: { !offSet.contains(part.rawValue) },
                            set: { on in
                                var off = offSet
                                if on { off.remove(part.rawValue) } else { off.insert(part.rawValue) }
                                switchedOff = off.sorted().joined(separator: ",")
                                bluetooth.send(.scene(part, on))
                            }
                        ))
                    }
                    slider("Caustic intensity", value: $causticIntensity, in: 0...3, format: "%.2f", unit: "") {
                        .causticIntensity(Float($0))
                    }
                    slider("Bob with phone movement", value: $motionReaction, in: 0...2, format: "%.2f", unit: "") {
                        .motionReaction(Float($0))
                    }
                    slider("Debris in the water", value: $debrisAmount, in: 0...2, format: "%.2f", unit: "") {
                        .debrisAmount(Float($0))
                    }
                    slider("Water motion", value: $waterMotion, in: 0...2, format: "%.2f", unit: "") {
                        .waterMotion(Float($0))
                    }
                    slider("Distortion", value: $distortion, in: 0...1, format: "%.2f", unit: "") {
                        .distortion(Float($0))
                    }
                }

                Section {
                } footer: {
                    Text("Changes show on the main app right away and are saved there by themselves; it starts with them next time. On connecting, this tab shows the main app's scene.")
                }
            }
            .disabled(!bluetooth.isConnected)
            .navigationTitle("Scene")
            .onChange(of: bluetooth.mainState?.scene) { _, scene in
                if let scene { show(scene) }
            }
            .onAppear {
                if let scene = bluetooth.mainState?.scene { show(scene) }
            }
        }
    }

    private var waterColor: SIMD3<Float> {
        let parts = water.split(separator: ",").compactMap { Float($0) }
        return parts.count == 3 ? SIMD3(parts[0], parts[1], parts[2]) : SceneLook.defaultWater
    }

    private var offSet: Set<String> { Set(switchedOff.split(separator: ",").map(String.init)) }

    private func setWater(_ color: SIMD3<Float>) {
        let clamped = simd_clamp(color, .zero, .one)
        water = "\(clamped.x),\(clamped.y),\(clamped.z)"
        bluetooth.send(.waterColor(clamped))
    }

    private static func color(_ linear: SIMD3<Float>) -> Color {
        Color(.sRGBLinear, red: Double(linear.x), green: Double(linear.y), blue: Double(linear.z))
    }

    private func slider(
        _ title: String,
        value: Binding<Double>,
        in range: ClosedRange<Double>,
        format: String,
        unit: String,
        setting: @escaping (Double) -> RemoteSetting
    ) -> some View {
        VStack(alignment: .leading) {
            LabeledContent(title) {
                Text("\(String(format: format, value.wrappedValue))\(unit)").monospacedDigit()
            }
            Slider(value: value, in: range) { Text(title) }
                .onChange(of: value.wrappedValue) { _, v in bluetooth.send(setting(v)) }
        }
    }

    /// The main app's scene, into the controls here.
    private func show(_ scene: SceneSettings) {
        water = "\(scene.water.x),\(scene.water.y),\(scene.water.z)"
        whiteBalance = Double(scene.whiteBalance)
        fieldOfView = Double(scene.fieldOfView)
        cameraZ = Double(scene.cameraZ)
        vignette = Double(scene.vignette)
        vignetteSize = Double(scene.vignetteSize)
        vignetteSoftness = Double(scene.vignetteSoftness)
        brightness = Double(scene.brightness)
        causticIntensity = Double(scene.causticIntensity)
        motionReaction = Double(scene.motionReaction)
        debrisAmount = Double(scene.debrisAmount)
        waterMotion = Double(scene.waterMotion)
        distortion = Double(scene.distortion)
        switchedOff = scene.off.sorted().joined(separator: ",")
    }

}
