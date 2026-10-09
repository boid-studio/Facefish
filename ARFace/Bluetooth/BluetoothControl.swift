import CoreBluetooth
import Foundation
import Observation

enum ControlCommand: String, Codable, CaseIterable, Identifiable {
    case ping
    case mirrorOn
    case mirrorOff

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ping: "Ping"
        case .mirrorOn: "Mirror on"
        case .mirrorOff: "Mirror off"
        }
    }
}

/// A setting value pushed from the control app to the main app.
enum RemoteSetting: Codable, Equatable {
    case centerFace
    case mirror(Bool)
    case faceCalibration(Bool)
    case lipSeal(Float)
    case puckerPriority(Float)
    case cameraZ(Float)

    /// Settings with the same key replace each other while queued.
    var key: String {
        switch self {
        case .centerFace: "centerFace"
        case .mirror: "mirror"
        case .faceCalibration: "faceCalibration"
        case .lipSeal: "lipSeal"
        case .puckerPriority: "puckerPriority"
        case .cameraZ: "cameraZ"
        }
    }

    var title: String {
        switch self {
        case .centerFace: "Center face"
        case .mirror(let on): "Mirror \(on ? "on" : "off")"
        case .faceCalibration(let on): "Face calibration \(on ? "on" : "off")"
        case .lipSeal(let v): "Lip seal \(String(format: "%.2f", v))"
        case .puckerPriority(let v): "Pucker priority \(String(format: "%.2f", v))"
        case .cameraZ(let v): "Camera Z \(String(format: "%.2f", v))"
        }
    }
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
    private static let handshake = Data("facefish-control-v1".utf8)

    private(set) var isControlMode = false
    private(set) var isPairing = false
    private(set) var isConnected = false
    private(set) var isConnecting = false
    private(set) var isSending = false
    private(set) var status = "Bluetooth control is off."
    private(set) var devices: [CBPeripheral] = []
    private(set) var receivedCommands: [ReceivedControlCommand] = []
    var onCommand: ((ControlCommand) -> Void)?
    var onSetting: ((RemoteSetting) -> Void)?

    @ObservationIgnored private var centralManager: CBCentralManager?
    @ObservationIgnored private var peripheralManager: CBPeripheralManager?
    @ObservationIgnored private var peer: CBPeripheral?
    @ObservationIgnored private var commandCharacteristic: CBCharacteristic?
    @ObservationIgnored private var hostedCharacteristic: CBMutableCharacteristic?
    @ObservationIgnored private var authorizedCentral: UUID?
    @ObservationIgnored private var connectionTimeout: Timer?
    @ObservationIgnored private var pendingCommand: ControlPayload?
    /// Settings waiting for the in-flight write to finish; only the latest value per key is kept.
    @ObservationIgnored private var queuedSettings: [RemoteSetting] = []
    @ObservationIgnored private var pendingCompletion: ((Bool) -> Void)?

    func setControlMode(_ enabled: Bool) {
        guard enabled != isControlMode else { return }
        stop()
        isControlMode = enabled
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

    func connect(to device: CBPeripheral) {
        guard isControlMode, isPairing, !isConnecting,
              centralManager?.state == .poweredOn else { return }
        centralManager?.stopScan()
        devices = []
        peer = device
        device.delegate = self
        isConnecting = true
        status = "Pairing with \(device.name ?? "Facefish")…"
        centralManager?.connect(device)
        connectionTimeout = Timer.scheduledTimer(withTimeInterval: 30, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.failConnection("Pairing timed out. Try again with both apps open.")
            }
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
            queuedSettings.removeAll { $0.key == setting.key }
            queuedSettings.append(setting)
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
        centralManager?.stopScan()
        if let peer {
            peer.delegate = nil
            centralManager?.cancelPeripheralConnection(peer)
        }
        peer = nil
        commandCharacteristic = nil
        pendingCommand = nil
        queuedSettings = []
        let completion = pendingCompletion
        pendingCompletion = nil
        completion?(false)
        peripheralManager?.stopAdvertising()
        peripheralManager?.removeAllServices()
        hostedCharacteristic = nil
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
        let service = CBMutableService(type: Self.serviceID, primary: true)
        service.characteristics = [characteristic]
        hostedCharacteristic = characteristic
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
        failConnection("Connection failed. Try pairing again.")
    }

    func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: Error?
    ) {
        guard peer === peripheral else { return }
        failConnection("Main app disconnected. Pair again to reconnect.")
    }
}

extension BluetoothControl: @preconcurrency CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard peer === peripheral else { return }
        guard error == nil,
              let service = peripheral.services?.first(where: { $0.uuid == Self.serviceID }) else {
            failConnection("Facefish control service is unavailable.")
            return
        }
        peripheral.discoverCharacteristics([Self.commandID], for: service)
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
        peripheral.setNotifyValue(true, for: characteristic)
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateNotificationStateFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        guard peer === peripheral, characteristic === commandCharacteristic else { return }
        guard error == nil, characteristic.isNotifying else {
            failConnection("Pairing was declined or the main app stopped control.")
            return
        }
        peripheral.readValue(for: characteristic)
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        guard peer === peripheral, characteristic === commandCharacteristic, isConnecting else { return }
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
            write(.setting(queuedSettings.removeFirst()))
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didModifyServices invalidatedServices: [CBService]) {
        guard peer === peripheral,
              invalidatedServices.contains(where: { $0.uuid == Self.serviceID }) else { return }
        failConnection("Main app stopped control. Pair again to reconnect.")
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
            status = "Ready to pair. Select this device in the control app."
        }
    }

    func peripheralManager(
        _ peripheral: CBPeripheralManager,
        central: CBCentral,
        didSubscribeTo characteristic: CBCharacteristic
    ) {
        guard !isControlMode, isPairing, authorizedCentral == nil,
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
        stop()
        status = "Control app disconnected. The main app continues independently."
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveRead request: CBATTRequest) {
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
