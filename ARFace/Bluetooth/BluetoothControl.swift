import CoreBluetooth
import Foundation
import Observation

enum ControlCommand: String, Codable, CaseIterable, Identifiable {
    case ping
    case mirrorOn
    case mirrorOff
    case swimLap
    case spin
    case loop
    case blush
    case blowBubbles
    case stare
    case shush
    case sealed
    case hide
    case show

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ping: "Ping"
        case .mirrorOn: "Mirror on"
        case .mirrorOff: "Mirror off"
        case .swimLap: "Swim a lap"
        case .spin: "Spin"
        case .loop: "Loop"
        case .blush: "Blush"
        case .blowBubbles: "Blow bubbles"
        case .stare: "Stare"
        case .shush: "Shush"
        case .sealed: "My lips are sealed"
        case .hide: "Hide"
        case .show: "Show"
        }
    }
}

/// A setting value pushed from the control app to the main app.
enum RemoteSetting: Codable, Equatable {
    case centerFace
    case mirror(Bool)
    case phoneOrientation(PhoneOrientation)
    case externalDisplayUpsideDown(Bool)
    case faceCalibration(Bool)
    case lipSeal(Float)
    case puckerPriority(Float)
    /// How far down the performer looks to look straight out (FaceCalibration).
    case gazeCorrection(Float)
    case cameraZ(Float)
    /// 0 = natural, 1 = big stage acting (AvatarController).
    case acting(Float)
    /// Put an accessory on or take it off (the hat button).
    case accessory(Accessory, Bool)
    // The scene (the Scene tab).
    /// The water's colour, linear RGB (SceneLook).
    case waterColor(SIMD3<Float>)
    /// -1 cool ... +1 warm.
    case whiteBalance(Float)
    /// The camera's vertical field of view, degrees.
    case fieldOfView(Float)
    /// Darkening toward the edges 0...1, and where it starts (SceneLook).
    case vignette(Float)
    case vignetteSize(Float)
    case vignetteSoftness(Float)
    /// How light the water is, 0...1.3.
    case waterBrightness(Float)
    case causticIntensity(Float)
    /// How much she bobs as the phone moves, 0...2.
    case motionReaction(Float)
    /// The debris in the water: how much, and how much it moves (0...2).
    case debrisAmount(Float)
    case waterMotion(Float)
    /// The image wavering as if seen through moving water, 0...1.
    case distortion(Float)
    case scene(SceneSwitch, Bool)
    /// Keep the scene as it is now on the main app (loaded at its next launch).
    case saveScene

    /// Settings with the same key replace each other while queued.
    var key: String {
        switch self {
        case .centerFace: "centerFace"
        case .mirror: "mirror"
        case .phoneOrientation: "phoneOrientation"
        case .externalDisplayUpsideDown: "externalDisplayUpsideDown"
        case .faceCalibration: "faceCalibration"
        case .lipSeal: "lipSeal"
        case .puckerPriority: "puckerPriority"
        case .gazeCorrection: "gazeCorrection"
        case .cameraZ: "cameraZ"
        case .acting: "acting"
        case .accessory(let accessory, _): "accessory.\(accessory.rawValue)"
        case .waterColor: "waterColor"
        case .whiteBalance: "whiteBalance"
        case .fieldOfView: "fieldOfView"
        case .vignette: "vignette"
        case .vignetteSize: "vignetteSize"
        case .vignetteSoftness: "vignetteSoftness"
        case .waterBrightness: "waterBrightness"
        case .causticIntensity: "causticIntensity"
        case .motionReaction: "motionReaction"
        case .debrisAmount: "debrisAmount"
        case .waterMotion: "waterMotion"
        case .distortion: "distortion"
        case .scene(let part, _): "scene.\(part.rawValue)"
        case .saveScene: "saveScene"
        }
    }

    /// Part of the scene (the Scene tab), which the main app saves as it changes.
    var isScene: Bool {
        switch self {
        case .waterColor, .whiteBalance, .fieldOfView, .cameraZ, .vignette, .vignetteSize,
             .vignetteSoftness, .waterBrightness, .causticIntensity, .motionReaction, .scene,
             .debrisAmount, .waterMotion, .distortion:
            true
        default:
            false
        }
    }

    var title: String {
        switch self {
        case .centerFace: "Center face"
        case .mirror(let on): "Mirror \(on ? "on" : "off")"
        case .phoneOrientation(let orientation): "Phone orientation: \(orientation.title)"
        case .externalDisplayUpsideDown(let on): "External display upside down \(on ? "on" : "off")"
        case .faceCalibration(let on): "Face calibration \(on ? "on" : "off")"
        case .lipSeal(let v): "Lip seal \(String(format: "%.2f", v))"
        case .puckerPriority(let v): "Pucker priority \(String(format: "%.2f", v))"
        case .gazeCorrection(let v): "Gaze correction \(String(format: "%.2f", v))"
        case .cameraZ(let v): "Camera Z \(String(format: "%.2f", v))"
        case .acting(let v): "Acting \(String(format: "%.2f", v))"
        case .accessory(let accessory, let on): "\(accessory.title) \(on ? "on" : "off")"
        case .waterColor: "Water colour"
        case .whiteBalance(let v): "White balance \(String(format: "%.2f", v))"
        case .fieldOfView(let v): "Field of view \(String(format: "%.0f", v))°"
        case .vignette(let v): "Vignette \(String(format: "%.2f", v))"
        case .vignetteSize(let v): "Vignette size \(String(format: "%.2f", v))"
        case .vignetteSoftness(let v): "Vignette softness \(String(format: "%.2f", v))"
        case .waterBrightness(let v): "Background brightness \(String(format: "%.2f", v))"
        case .causticIntensity(let v): "Caustic intensity \(String(format: "%.2f", v))"
        case .motionReaction(let v): "Motion bob \(String(format: "%.2f", v))"
        case .debrisAmount(let v): "Debris \(String(format: "%.2f", v))"
        case .waterMotion(let v): "Water motion \(String(format: "%.2f", v))"
        case .distortion(let v): "Distortion \(String(format: "%.2f", v))"
        case .scene(let part, let on): "\(part.title) \(on ? "on" : "off")"
        case .saveScene: "Save scene settings"
        }
    }
}

/// What the main app has now, for the control app to show on connecting (the main app is where
/// it lives): the scene, the accessories the fish model has and those she's wearing. Short keys,
/// so it fits one Bluetooth read.
nonisolated struct MainAppState: Codable, Equatable {
    var scene = SceneSettings()
    var available: [Accessory] = []
    var worn: [Accessory] = []

    enum CodingKeys: String, CodingKey { case scene = "s", available = "a", worn = "h" }
}

enum ControlPayload {
    case command(ControlCommand)
    case setting(RemoteSetting)

    var title: String {
        switch self {
        case .command(let c): c.title
        case .setting(let s): s.title
        }
    }
}

struct ReceivedControlCommand: Identifiable {
    let id = UUID()
    let date = Date()
    let payload: ControlPayload
}

private struct ControlMessage: Codable {
    let version: Int
    var command: ControlCommand?
    var setting: RemoteSetting?
}

@Observable
@MainActor
final class BluetoothControl: NSObject {
    static let shared = BluetoothControl()
    private static let serviceID = CBUUID(string: "B9AB8300-8C79-48FA-B127-FAFCEB570001")
    private static let commandID = CBUUID(string: "B9AB8300-8C79-48FA-B127-FAFCEB570002")
    /// Read-only: the main app's state as it is now (MainAppState JSON), for the control app.
    private static let sceneID = CBUUID(string: "B9AB8300-8C79-48FA-B127-FAFCEB570003")
    private static let handshake = Data("facefish-control-v1".utf8)

    private static let controlModeKey = "bluetooth.controlMode"
    private static let mainAppKey = "bluetooth.mainApp"
    /// This phone is the control app (kept between launches).
    private(set) var isControlMode = UserDefaults.standard.bool(forKey: BluetoothControl.controlModeKey)
    /// Control app: the main app it last connected to, remembered so it reconnects by itself.
    private(set) var rememberedMainApp: UUID? = UserDefaults.standard.string(forKey: BluetoothControl.mainAppKey)
        .flatMap(UUID.init(uuidString:))
    private(set) var isPairing = false
    private(set) var isConnected = false
    private(set) var isConnecting = false
    private(set) var isSending = false
    private(set) var status = "Bluetooth control is off."
    private(set) var devices: [CBPeripheral] = []
    private(set) var receivedCommands: [ReceivedControlCommand] = []
    var onCommand: ((ControlCommand) -> Void)?
    var onSetting: ((RemoteSetting) -> Void)?
    /// Main app: what it has now (scene, accessories), for the control app to read on connecting.
    var stateProvider: (() -> MainAppState)?
    /// Control app: the main app's state, read on connecting (the main app is where it lives).
    private(set) var mainState: MainAppState?

    @ObservationIgnored private var centralManager: CBCentralManager?
    @ObservationIgnored private var peripheralManager: CBPeripheralManager?
    @ObservationIgnored private var peer: CBPeripheral?
    @ObservationIgnored private var commandCharacteristic: CBCharacteristic?
    @ObservationIgnored private var hostedCharacteristic: CBMutableCharacteristic?
    @ObservationIgnored private var sceneCharacteristic: CBCharacteristic?
    @ObservationIgnored private var hostedSceneCharacteristic: CBMutableCharacteristic?
    /// The scene as served for the read in progress (a long read comes in pieces).
    @ObservationIgnored private var servedScene = Data()
    @ObservationIgnored private var authorizedCentral: UUID?
    @ObservationIgnored private var connectionTimeout: Timer?
    @ObservationIgnored private var retryTimer: Timer?
    @ObservationIgnored private var pendingCommand: ControlPayload?
    /// Settings waiting for the in-flight write to finish; only the latest value per key is kept.
    @ObservationIgnored private var queuedSettings: [(setting: RemoteSetting, completion: ((Bool) -> Void)?)] = []
    @ObservationIgnored private var pendingCompletion: ((Bool) -> Void)?

    func setControlMode(_ enabled: Bool) {
        guard enabled != isControlMode else { return }
        stop()
        isControlMode = enabled
        UserDefaults.standard.set(enabled, forKey: Self.controlModeKey)
        start()
    }

    /// Starts Bluetooth control and keeps it going, with nothing to press: the main app waits for
    /// its control app (it can connect any time), the control app reconnects to the main app it
    /// remembers, or looks for one. The first time two phones meet, iOS asks once to pair them.
    func start() {
        guard !isConnected, !isConnecting, !isPairing else { return }
        startPairing()
    }

    /// Control app: forgets the main app, to pair with another.
    func forgetMainApp() {
        rememberedMainApp = nil
        UserDefaults.standard.removeObject(forKey: Self.mainAppKey)
        stop()
        start()
    }

    /// Control app: lost the remembered main app (it went away, or isn't running yet): tries again
    /// shortly, quietly, until it's back.
    private func reconnectSoon(_ message: String, after delay: TimeInterval = 2) {
        let resume = isControlMode
        stop()
        status = message
        guard resume else { return }
        retryTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.start() }
        }
    }

    func startPairing() {
        stop()
        isPairing = true
        status = "Starting Bluetooth…"
        if isControlMode {
            if centralManager == nil {
                centralManager = CBCentralManager(delegate: self, queue: .main)
            } else {
                startScanning()
            }
        } else if peripheralManager == nil {
            peripheralManager = CBPeripheralManager(delegate: self, queue: .main)
        } else {
            publishService()
        }
    }

    /// `waits`: the remembered main app; the connection waits for it, however long.
    func connect(to device: CBPeripheral, waits: Bool = false) {
        guard isControlMode, isPairing, !isConnecting,
              centralManager?.state == .poweredOn else { return }
        centralManager?.stopScan()
        devices = []
        peer = device
        device.delegate = self
        isConnecting = true
        status = waits ? "Reconnecting to the main app…" : "Pairing with \(device.name ?? "Facefish")…"
        centralManager?.connect(device)
        guard !waits else { return }
        connectionTimeout = Timer.scheduledTimer(withTimeInterval: 30, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.failConnection("Pairing timed out. Try again with both apps open.")
            }
        }
    }

    /// A connection problem: the remembered main app is retried by itself; a new one reports it.
    private func lost(_ peripheral: CBPeripheral, _ message: String) {
        if isControlMode, peripheral.identifier == rememberedMainApp {
            reconnectSoon("Main app not reachable. Reconnecting…")
        } else {
            failConnection(message)
        }
    }

    func send(_ command: ControlCommand) {
        guard !isSending else { return }
        write(.command(command))
    }

    /// Sends a setting, coalescing rapid changes (e.g. slider drags) while a write is in flight.
    /// `completion` reports whether the main app acknowledged the write; it is not
    /// called if the setting is coalesced with a later value.
    func send(_ setting: RemoteSetting, completion: ((Bool) -> Void)? = nil) {
        guard isControlMode, isConnected else {
            completion?(false)
            return
        }
        if isSending {
            queuedSettings.removeAll { $0.setting.key == setting.key }
            queuedSettings.append((setting, completion))
        } else {
            write(.setting(setting), completion: completion)
        }
    }

    private func write(_ payload: ControlPayload, completion: ((Bool) -> Void)? = nil) {
        guard isControlMode, isConnected, !isSending,
              let peer, let commandCharacteristic else {
            completion?(false)
            return
        }
        var message = ControlMessage(version: 1)
        switch payload {
        case .command(let c): message.command = c
        case .setting(let s): message.setting = s
        }
        do {
            let data = try JSONEncoder().encode(message)
            guard data.count <= peer.maximumWriteValueLength(for: .withResponse) else {
                status = "Command is too large for this connection."
                return
            }
            pendingCommand = payload
            pendingCompletion = completion
            isSending = true
            peer.writeValue(data, for: commandCharacteristic, type: .withResponse)
        } catch {
            status = "Unable to encode command."
        }
    }

    /// Control app: reads the main app's state again (mainState).
    func refreshScene() {
        guard isControlMode, isConnected, let peer, let sceneCharacteristic else { return }
        peer.readValue(for: sceneCharacteristic)
    }

    func clearLog() {
        receivedCommands.removeAll()
    }

    func stop() {
        isPairing = false
        isConnected = false
        isConnecting = false
        isSending = false
        connectionTimeout?.invalidate()
        connectionTimeout = nil
        retryTimer?.invalidate()
        retryTimer = nil
        centralManager?.stopScan()
        if let peer {
            peer.delegate = nil
            centralManager?.cancelPeripheralConnection(peer)
        }
        peer = nil
        commandCharacteristic = nil
        sceneCharacteristic = nil
        mainState = nil
        pendingCommand = nil
        let queued = queuedSettings
        queuedSettings = []
        queued.forEach { $0.completion?(false) }
        let completion = pendingCompletion
        pendingCompletion = nil
        completion?(false)
        peripheralManager?.stopAdvertising()
        peripheralManager?.removeAllServices()
        hostedCharacteristic = nil
        hostedSceneCharacteristic = nil
        authorizedCentral = nil
        devices = []
        status = "Bluetooth control is off."
    }

    private func stateDescription(_ state: CBManagerState) -> String {
        switch state {
        case .poweredOff: "Bluetooth is off. Enable it in Settings."
        case .unauthorized: "Bluetooth permission denied. Allow access in Settings."
        case .unsupported: "Bluetooth LE is unavailable on this device."
        case .resetting: "Bluetooth is resetting…"
        case .unknown: "Waiting for Bluetooth…"
        case .poweredOn: "Bluetooth is ready."
        @unknown default: "Bluetooth is unavailable."
        }
    }

    private func startScanning() {
        guard isControlMode, isPairing, let centralManager else { return }
        guard centralManager.state == .poweredOn else {
            status = stateDescription(centralManager.state)
            return
        }
        if let rememberedMainApp,
           let mainApp = centralManager.retrievePeripherals(withIdentifiers: [rememberedMainApp]).first {
            connect(to: mainApp, waits: true)
            return
        }
        status = "Searching for main apps…"
        centralManager.scanForPeripherals(withServices: [Self.serviceID])
    }

    private func publishService() {
        guard !isControlMode, isPairing, let peripheralManager else { return }
        guard peripheralManager.state == .poweredOn else {
            status = stateDescription(peripheralManager.state)
            return
        }
        guard hostedCharacteristic == nil else { return }
        let characteristic = CBMutableCharacteristic(
            type: Self.commandID,
            properties: [.read, .write, .notifyEncryptionRequired],
            value: nil,
            permissions: [.readEncryptionRequired, .writeEncryptionRequired]
        )
        let scene = CBMutableCharacteristic(
            type: Self.sceneID,
            properties: [.read],
            value: nil,
            permissions: [.readEncryptionRequired]
        )
        let service = CBMutableService(type: Self.serviceID, primary: true)
        service.characteristics = [characteristic, scene]
        hostedCharacteristic = characteristic
        hostedSceneCharacteristic = scene
        peripheralManager.add(service)
    }

    private func failConnection(_ message: String) {
        stop()
        status = message
    }
}

extension BluetoothControl: @preconcurrency CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        guard isControlMode else { return }
        if central.state == .poweredOn {
            startScanning()
        } else if central.state == .unknown || central.state == .resetting {
            let shouldResumePairing = isPairing
            stop()
            isPairing = shouldResumePairing
            status = stateDescription(central.state)
        } else {
            let message = stateDescription(central.state)
            stop()
            status = message
        }
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        guard isControlMode, isPairing, !isConnecting,
              !devices.contains(where: { $0.identifier == peripheral.identifier }) else { return }
        if devices.count < 30 { devices.append(peripheral) }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        guard peer === peripheral, isControlMode, isConnecting else {
            central.cancelPeripheralConnection(peripheral)
            return
        }
        peripheral.discoverServices([Self.serviceID])
    }

    func centralManager(
        _ central: CBCentralManager,
        didFailToConnect peripheral: CBPeripheral,
        error: Error?
    ) {
        guard peer === peripheral else { return }
        lost(peripheral, "Connection failed. Try pairing again.")
    }

    func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: Error?
    ) {
        guard peer === peripheral else { return }
        lost(peripheral, "Main app disconnected. Find it again to reconnect.")
    }
}

extension BluetoothControl: @preconcurrency CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard peer === peripheral else { return }
        guard error == nil,
              let service = peripheral.services?.first(where: { $0.uuid == Self.serviceID }) else {
            lost(peripheral, "Facefish control service is unavailable.")
            return
        }
        peripheral.discoverCharacteristics([Self.commandID, Self.sceneID], for: service)
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Error?
    ) {
        guard peer === peripheral else { return }
        guard error == nil,
              let characteristic = service.characteristics?.first(where: { $0.uuid == Self.commandID }),
              characteristic.properties.contains(.read),
              characteristic.properties.contains(.write),
              characteristic.properties.contains(.notifyEncryptionRequired) ||
                characteristic.properties.contains(.notify) else {
            failConnection("This main app does not support control commands.")
            return
        }
        commandCharacteristic = characteristic
        // An older main app has no scene to read; control still works.
        sceneCharacteristic = service.characteristics?.first { $0.uuid == Self.sceneID }
        peripheral.setNotifyValue(true, for: characteristic)
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateNotificationStateFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        guard peer === peripheral, characteristic === commandCharacteristic else { return }
        guard error == nil, characteristic.isNotifying else {
            lost(peripheral, "Pairing was declined or the main app stopped control.")
            return
        }
        peripheral.readValue(for: characteristic)
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        guard peer === peripheral else { return }
        if characteristic === sceneCharacteristic {
            // The main app's state.
            if error == nil, let data = characteristic.value,
               let state = try? JSONDecoder().decode(MainAppState.self, from: data) {
                mainState = state
            }
            return
        }
        guard characteristic === commandCharacteristic, isConnecting else { return }
        guard error == nil, characteristic.value == Self.handshake else {
            failConnection("Pairing failed. Enable pairing on the main app and try again.")
            return
        }
        connectionTimeout?.invalidate()
        connectionTimeout = nil
        isConnecting = false
        isPairing = false
        isConnected = true
        status = "Connected to \(peripheral.name ?? "Facefish")."
        // Remembered: from now on it reconnects by itself.
        rememberedMainApp = peripheral.identifier
        UserDefaults.standard.set(peripheral.identifier.uuidString, forKey: Self.mainAppKey)
        refreshScene()
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didWriteValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        guard peer === peripheral, characteristic === commandCharacteristic else { return }
        isSending = false
        status = error == nil
            ? "\(pendingCommand?.title ?? "Command") delivered."
            : "Command was not delivered. Try again."
        pendingCommand = nil
        let completion = pendingCompletion
        pendingCompletion = nil
        completion?(error == nil)
        if !queuedSettings.isEmpty {
            let next = queuedSettings.removeFirst()
            write(.setting(next.setting), completion: next.completion)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didModifyServices invalidatedServices: [CBService]) {
        guard peer === peripheral,
              invalidatedServices.contains(where: { $0.uuid == Self.serviceID }) else { return }
        lost(peripheral, "Main app stopped control. Find it again to reconnect.")
    }
}

extension BluetoothControl: @preconcurrency CBPeripheralManagerDelegate {
    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        guard !isControlMode else { return }
        if peripheral.state == .poweredOn {
            publishService()
        } else if peripheral.state == .unknown || peripheral.state == .resetting {
            let shouldResumePairing = isPairing
            stop()
            isPairing = shouldResumePairing
            status = stateDescription(peripheral.state)
        } else {
            let message = stateDescription(peripheral.state)
            stop()
            status = message
        }
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, didAdd service: CBService, error: Error?) {
        guard !isControlMode, isPairing,
              service.characteristics?.first === hostedCharacteristic else { return }
        guard error == nil else {
            failConnection("Unable to start pairing. Try again.")
            return
        }
        peripheral.startAdvertising([
            CBAdvertisementDataServiceUUIDsKey: [Self.serviceID],
            CBAdvertisementDataLocalNameKey: "Facefish"
        ])
    }

    func peripheralManagerDidStartAdvertising(_ peripheral: CBPeripheralManager, error: Error?) {
        guard !isControlMode, isPairing else { return }
        if error != nil {
            failConnection("Unable to advertise. Try pairing again.")
        } else {
            status = "Waiting for the control app. It connects by itself once paired."
        }
    }

    func peripheralManager(
        _ peripheral: CBPeripheralManager,
        central: CBCentral,
        didSubscribeTo characteristic: CBCharacteristic
    ) {
        // Any time (no pairing switch to reach inside the helmet): the link is encrypted, so only a
        // phone paired with this one in iOS (asked once, the first time) gets this far.
        guard !isControlMode, authorizedCentral == nil,
              characteristic === hostedCharacteristic else { return }
        authorizedCentral = central.identifier
        isConnected = true
        isPairing = false
        peripheral.stopAdvertising()
        status = "Control app connected."
    }

    func peripheralManager(
        _ peripheral: CBPeripheralManager,
        central: CBCentral,
        didUnsubscribeFrom characteristic: CBCharacteristic
    ) {
        guard central.identifier == authorizedCentral,
              characteristic === hostedCharacteristic else { return }
        // Waits for it (or another) to come back.
        authorizedCentral = nil
        isConnected = false
        isPairing = true
        peripheral.startAdvertising([
            CBAdvertisementDataServiceUUIDsKey: [Self.serviceID],
            CBAdvertisementDataLocalNameKey: "Facefish"
        ])
        status = "Control app disconnected. Waiting for it to reconnect…"
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveRead request: CBATTRequest) {
        if !isControlMode, request.characteristic === hostedSceneCharacteristic,
           request.central.identifier == authorizedCentral {
            // The state as it is now; a long read comes in pieces, all from the same snapshot.
            if request.offset == 0 {
                servedScene = stateProvider.flatMap { try? JSONEncoder().encode($0()) } ?? Data()
            }
            guard request.offset <= servedScene.count else {
                peripheral.respond(to: request, withResult: .invalidOffset)
                return
            }
            request.value = servedScene.subdata(in: request.offset..<servedScene.count)
            peripheral.respond(to: request, withResult: .success)
            return
        }
        guard !isControlMode, request.characteristic === hostedCharacteristic,
              request.central.identifier == authorizedCentral else {
            peripheral.respond(to: request, withResult: .insufficientAuthorization)
            return
        }
        guard request.offset <= Self.handshake.count else {
            peripheral.respond(to: request, withResult: .invalidOffset)
            return
        }
        request.value = Self.handshake.subdata(in: request.offset..<Self.handshake.count)
        peripheral.respond(to: request, withResult: .success)
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
        guard let request = requests.first else { return }
        guard !isControlMode, isConnected,
              request.central.identifier == authorizedCentral,
              request.characteristic === hostedCharacteristic else {
            peripheral.respond(to: request, withResult: .insufficientAuthorization)
            return
        }
        guard requests.count == 1 else {
            peripheral.respond(to: request, withResult: .requestNotSupported)
            return
        }
        guard request.offset == 0 else {
            peripheral.respond(to: request, withResult: .invalidOffset)
            return
        }
        guard let data = request.value, data.count <= 256,
              let message = try? JSONDecoder().decode(ControlMessage.self, from: data),
              message.version == 1 else {
            peripheral.respond(to: request, withResult: .unlikelyError)
            return
        }
        let payload: ControlPayload
        if let command = message.command {
            payload = .command(command)
            onCommand?(command)
        } else if let setting = message.setting {
            payload = .setting(setting)
            onSetting?(setting)
        } else {
            peripheral.respond(to: request, withResult: .unlikelyError)
            return
        }
        receivedCommands.insert(ReceivedControlCommand(payload: payload), at: 0)
        if receivedCommands.count > 100 { receivedCommands.removeLast() }
        peripheral.respond(to: request, withResult: .success)
    }
}
