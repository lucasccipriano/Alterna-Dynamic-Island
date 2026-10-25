import AppKit
import IOBluetooth

struct BluetoothDevice: Identifiable, Equatable {
    let id: String          // endereço
    let name: String
    let isConnected: Bool
    let isPaired: Bool
    let symbol: String
}

/// Bluetooth com IOBluetooth: liga/desliga, conecta, desconecta, procura e pareia.
@MainActor
final class BluetoothManager: NSObject, ObservableObject {
    static let shared = BluetoothManager()

    @Published private(set) var isPoweredOn = false
    @Published private(set) var paired: [BluetoothDevice] = []
    @Published private(set) var nearby: [BluetoothDevice] = []
    @Published private(set) var isScanning = false
    @Published private(set) var busy: Set<String> = []
    @Published private(set) var message: String?

    private var inquiry: IOBluetoothDeviceInquiry?
    private var pairing: IOBluetoothDevicePair?
    private var connectNotification: IOBluetoothUserNotification?
    private var started = false

    private override init() { super.init() }

    /// Começa a observar só quando a página aparece (o macOS pede permissão de Bluetooth).
    func activate() {
        refresh()
        guard !started else { return }
        started = true
        connectNotification = IOBluetoothDevice.register(forConnectNotifications: self,
                                                         selector: #selector(deviceConnected(_:device:)))
    }

    func refresh() {
        isPoweredOn = Self.powerState()
        let devices = (IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice]) ?? []
        paired = devices
            .map(Self.makeDevice)
            .sorted { ($0.isConnected ? 0 : 1, $0.name) < ($1.isConnected ? 0 : 1, $1.name) }
    }

    // MARK: - Liga / desliga

    func setPower(_ on: Bool) {
        message = nil
        guard Self.setPowerState(on) else {
            message = "O macOS não deixou mudar o Bluetooth daqui. Use os Ajustes de Bluetooth."
            return
        }
        isPoweredOn = on
        if !on { stopScan() }
        // O controlador demora um pouco para mudar de estado.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in self?.refresh() }
    }

    // MARK: - Conectar / desconectar

    func toggleConnection(_ device: BluetoothDevice) {
        guard let bt = IOBluetoothDevice(addressString: device.id) else { return }
        message = nil
        busy.insert(device.id)
        if bt.isConnected() {
            bt.closeConnection()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                self?.busy.remove(device.id)
                self?.refresh()
            }
        } else {
            let status = bt.openConnection(self)
            if status != kIOReturnSuccess {
                busy.remove(device.id)
                message = "Não foi possível conectar \(device.name). Ele está ligado e por perto?"
            }
        }
    }

    @objc nonisolated func connectionComplete(_ device: IOBluetoothDevice!, status: IOReturn) {
        let address = device?.addressString ?? ""
        let name = device?.name ?? "o dispositivo"
        Task { @MainActor [self] in
            busy.remove(address)
            if status != kIOReturnSuccess {
                message = "Não foi possível conectar \(name)."
            }
            refresh()
        }
    }

    @objc nonisolated func deviceConnected(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        device.register(forDisconnectNotification: self, selector: #selector(deviceDisconnected(_:device:)))
        Task { @MainActor [self] in refresh() }
    }

    @objc nonisolated func deviceDisconnected(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        Task { @MainActor [self] in refresh() }
    }

    // MARK: - Procurar e parear

    func startScan() {
        guard isPoweredOn else { message = "Ligue o Bluetooth primeiro."; return }
        stopScan()
        message = nil
        nearby = []
        let inquiry = IOBluetoothDeviceInquiry(delegate: self)
        inquiry?.inquiryLength = 12
        inquiry?.updateNewDeviceNames = true
        self.inquiry = inquiry
        if inquiry?.start() == kIOReturnSuccess {
            isScanning = true
            IslandModel.shared.keepOpen = true
        } else {
            message = "Não foi possível procurar dispositivos."
        }
    }

    func stopScan() {
        inquiry?.stop()
        inquiry = nil
        isScanning = false
    }

    func pair(_ device: BluetoothDevice) {
        guard let bt = IOBluetoothDevice(addressString: device.id),
              let pairing = IOBluetoothDevicePair(device: bt) else { return }
        stopScan()
        message = "Pareando com \(device.name)… Confirme no dispositivo, se ele pedir."
        busy.insert(device.id)
        pairing.delegate = self
        self.pairing = pairing
        if pairing.start() != kIOReturnSuccess {
            busy.remove(device.id)
            message = "Não foi possível parear \(device.name)."
        }
    }

    func openSystemSettings() {
        SettingsOpener.openSystemSettings("com.apple.BluetoothSettings")
    }

    // MARK: - Utilidades

    nonisolated private static func makeDevice(_ device: IOBluetoothDevice) -> BluetoothDevice {
        BluetoothDevice(id: device.addressString ?? UUID().uuidString,
                        name: device.name ?? device.addressString ?? "Dispositivo",
                        isConnected: device.isConnected(),
                        isPaired: device.isPaired(),
                        symbol: symbol(for: device))
    }

    nonisolated private static func symbol(for device: IOBluetoothDevice) -> String {
        let name = (device.name ?? "").lowercased()
        if name.contains("airpods max") { return "airpodsmax" }
        if name.contains("airpods pro") { return "airpodspro" }
        if name.contains("airpods") { return "airpods" }
        if name.contains("beats") { return "beats.headphones" }
        if name.contains("trackpad") { return "rectangle.and.hand.point.up.left.fill" }
        if name.contains("mouse") || name.contains("mx master") || name.contains("mx anywhere") { return "computermouse.fill" }
        if name.contains("keyboard") || name.contains("teclado") || name.contains("mx keys") { return "keyboard.fill" }
        if name.contains("iphone") { return "iphone" }
        if name.contains("ipad") { return "ipad" }
        if name.contains("watch") { return "applewatch" }
        if name.contains("controller") || name.contains("dualsense") || name.contains("xbox") { return "gamecontroller.fill" }

        let major = device.deviceClassMajor
        let minor = device.deviceClassMinor
        switch major {
        case 0x01: return "laptopcomputer"
        case 0x02: return "iphone"
        case 0x04: return "headphones"
        case 0x05:
            if minor & 0x10 != 0 { return "keyboard.fill" }
            if minor & 0x20 != 0 { return "computermouse.fill" }
            return "gamecontroller.fill"
        default: return "dot.radiowaves.left.and.right"
        }
    }

    nonisolated private static func powerState() -> Bool {
        typealias Getter = @convention(c) () -> Int32
        if let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "IOBluetoothPreferenceGetControllerPowerState") {
            return unsafeBitCast(symbol, to: Getter.self)() != 0
        }
        return IOBluetoothHostController.default()?.powerState == kBluetoothHCIPowerStateON
    }

    nonisolated private static func setPowerState(_ on: Bool) -> Bool {
        typealias Setter = @convention(c) (Int32) -> Void
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "IOBluetoothPreferenceSetControllerPowerState") else {
            return false
        }
        unsafeBitCast(symbol, to: Setter.self)(on ? 1 : 0)
        return true
    }
}

// MARK: - Delegados do IOBluetooth

extension BluetoothManager: IOBluetoothDeviceInquiryDelegate {
    nonisolated func deviceInquiryDeviceFound(_ sender: IOBluetoothDeviceInquiry!, device: IOBluetoothDevice!) {
        guard let device else { return }
        let found = BluetoothManager.makeDevice(device)
        Task { @MainActor [self] in addNearby(found) }
    }

    nonisolated func deviceInquiryDeviceNameUpdated(_ sender: IOBluetoothDeviceInquiry!, device: IOBluetoothDevice!,
                                                    devicesRemaining: UInt32) {
        guard let device else { return }
        let found = BluetoothManager.makeDevice(device)
        Task { @MainActor [self] in addNearby(found) }
    }

    nonisolated func deviceInquiryComplete(_ sender: IOBluetoothDeviceInquiry!, error: IOReturn, aborted: Bool) {
        Task { @MainActor [self] in
            isScanning = false
            IslandModel.shared.keepOpen = false
            if nearby.isEmpty && !aborted {
                message = "Nenhum dispositivo novo encontrado. Coloque-o em modo de pareamento e procure de novo."
            }
        }
    }

    private func addNearby(_ device: BluetoothDevice) {
        guard !device.isPaired else { return }
        if let index = nearby.firstIndex(where: { $0.id == device.id }) {
            nearby[index] = device
        } else {
            nearby.append(device)
        }
    }
}

extension BluetoothManager: IOBluetoothDevicePairDelegate {
    nonisolated func devicePairingUserConfirmationRequest(_ sender: Any!, numericValue: BluetoothNumericValue) {
        // Confirma o código numérico (o mesmo aparece no dispositivo).
        (sender as? IOBluetoothDevicePair)?.replyUserConfirmation(true)
    }

    nonisolated func devicePairingPINCodeRequest(_ sender: Any!) {
        // PIN padrão da maioria dos fones e caixas de som antigas.
        var pin = BluetoothPINCode()
        withUnsafeMutableBytes(of: &pin.data) { bytes in
            for (i, c) in "0000".utf8.enumerated() { bytes[i] = c }
        }
        (sender as? IOBluetoothDevicePair)?.replyPINCode(4, pinCode: &pin)
    }

    nonisolated func devicePairingFinished(_ sender: Any!, error: IOReturn) {
        let device = (sender as? IOBluetoothDevicePair)?.device()
        let address = device?.addressString ?? ""
        let name = device?.name ?? "o dispositivo"
        Task { @MainActor [self] in
            busy.remove(address)
            pairing = nil
            if error == kIOReturnSuccess {
                message = "\(name) pareado."
                nearby.removeAll { $0.id == address }
                device?.openConnection(self)
            } else {
                message = "Não foi possível parear \(name). Tente pelos Ajustes de Bluetooth."
            }
            refresh()
        }
    }
}
