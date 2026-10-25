import Foundation

// MARK: - Preferências globais (NSGlobalDomain, o mesmo que `defaults write -g`)

enum GlobalPrefs {
    static func value(_ key: String) -> Any? {
        CFPreferencesCopyValue(key as CFString,
                               kCFPreferencesAnyApplication,
                               kCFPreferencesCurrentUser,
                               kCFPreferencesAnyHost)
    }

    static func set(_ key: String, _ value: NSNumber) {
        CFPreferencesSetValue(key as CFString, value,
                              kCFPreferencesAnyApplication,
                              kCFPreferencesCurrentUser,
                              kCFPreferencesAnyHost)
        CFPreferencesSynchronize(kCFPreferencesAnyApplication,
                                 kCFPreferencesCurrentUser,
                                 kCFPreferencesAnyHost)
    }
}

// MARK: - Rolagem natural

/// No macOS a rolagem natural é UMA opção para mouse e trackpad juntos.
enum ScrollDirection {
    private static let key = "com.apple.swipescrolldirection"

    static var isNatural: Bool {
        (GlobalPrefs.value(key) as? NSNumber)?.boolValue ?? true
    }

    static func setNatural(_ natural: Bool) {
        // 1. Grava a preferência (é o que Ajustes do Sistema mostra e o que vale após reiniciar).
        GlobalPrefs.set(key, NSNumber(value: natural))

        // 2. Aplica na hora pela mesma função que o painel de Ajustes usa.
        typealias Setter = @convention(c) (Bool) -> Void
        let path = "/System/Library/PrivateFrameworks/PreferencePanesSupport.framework/PreferencePanesSupport"
        if let handle = dlopen(path, RTLD_LAZY),
           let symbol = dlsym(handle, "setSwipeScrollDirection") {
            unsafeBitCast(symbol, to: Setter.self)(natural)
        }

        // 3. Avisa os apps abertos.
        DistributedNotificationCenter.default().postNotificationName(
            Notification.Name("SwipeScrollDirectionDidChangeNotification"),
            object: nil, userInfo: nil, deliverImmediately: true)
    }
}

// MARK: - Velocidade do cursor

enum PointerDevice {
    case mouse, trackpad

    var preferenceKey: String {
        self == .mouse ? "com.apple.mouse.scaling" : "com.apple.trackpad.scaling"
    }

    var hidKey: String {
        self == .mouse ? "HIDMouseAcceleration" : "HIDTrackpadAcceleration"
    }
}

/// Velocidade no mesmo intervalo do controle de Ajustes do Sistema (0 a 3).
enum PointerSpeed {
    static let range: ClosedRange<Double> = 0...3

    static func current(_ device: PointerDevice) -> Double? {
        let value = GlobalPrefs.value(device.preferenceKey)
        if let number = value as? NSNumber { return number.doubleValue }
        if let text = value as? String { return Double(text) }
        return nil
    }

    static func set(_ device: PointerDevice, to value: Double) {
        let clamped = min(max(value, range.lowerBound), range.upperBound)
        GlobalPrefs.set(device.preferenceKey, NSNumber(value: clamped))
        HIDClient.setProperty(device.hidKey, NSNumber(value: Int(clamped * 65536)))
    }
}

/// Aplica a velocidade na hora nos dispositivos conectados (IOHIDEventSystemClient).
/// As funções são carregadas em tempo de execução porque não fazem parte do SDK do Swift.
private enum HIDClient {
    private typealias Create = @convention(c) (CFAllocator?) -> Unmanaged<AnyObject>?
    private typealias SetProperty = @convention(c) (AnyObject, CFString, AnyObject) -> UInt8
    private typealias CopyServices = @convention(c) (AnyObject) -> Unmanaged<CFArray>?

    private static let handle = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY)

    private static func load<T>(_ name: String, as type: T.Type) -> T? {
        guard let handle = Self.handle, let symbol = dlsym(handle, name) else { return nil }
        return unsafeBitCast(symbol, to: type)
    }

    static func setProperty(_ key: String, _ value: NSNumber) {
        guard let create = load("IOHIDEventSystemClientCreateSimpleClient", as: Create.self),
              let setClient = load("IOHIDEventSystemClientSetProperty", as: SetProperty.self),
              let copyServices = load("IOHIDEventSystemClientCopyServices", as: CopyServices.self),
              let setService = load("IOHIDServiceClientSetProperty", as: SetProperty.self),
              let client = create(kCFAllocatorDefault)?.takeRetainedValue()
        else { return }

        _ = setClient(client, key as CFString, value)

        if let services = copyServices(client)?.takeRetainedValue() {
            for service in services as NSArray {
                _ = setService(service as AnyObject, key as CFString, value)
            }
        }
    }
}
