import AudioToolbox
import CoreAudio
import Foundation

/// Leitura e escrita de propriedades do Core Audio, sem repetir boilerplate.
enum CA {
    static let system = AudioObjectID(kAudioObjectSystemObject)

    static func address(_ selector: AudioObjectPropertySelector,
                        _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
                        _ element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
    }

    static func has(_ object: AudioObjectID, _ addr: AudioObjectPropertyAddress) -> Bool {
        var a = addr
        return AudioObjectHasProperty(object, &a)
    }

    static func get<T>(_ object: AudioObjectID, _ addr: AudioObjectPropertyAddress, default value: T) -> T {
        var a = addr
        var result = value
        var size = UInt32(MemoryLayout<T>.size)
        let status = withUnsafeMutablePointer(to: &result) {
            AudioObjectGetPropertyData(object, &a, 0, nil, &size, $0)
        }
        return status == noErr ? result : value
    }

    @discardableResult
    static func set<T>(_ object: AudioObjectID, _ addr: AudioObjectPropertyAddress, _ value: T) -> OSStatus {
        var a = addr
        var v = value
        return withUnsafePointer(to: &v) {
            AudioObjectSetPropertyData(object, &a, 0, nil, UInt32(MemoryLayout<T>.size), $0)
        }
    }

    static func isSettable(_ object: AudioObjectID, _ addr: AudioObjectPropertyAddress) -> Bool {
        var a = addr
        var settable: DarwinBoolean = false
        return AudioObjectIsPropertySettable(object, &a, &settable) == noErr && settable.boolValue
    }

    static func array<T>(_ object: AudioObjectID, _ addr: AudioObjectPropertyAddress, of: T.Type) -> [T] {
        var a = addr
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(object, &a, 0, nil, &size) == noErr, size > 0 else { return [] }
        let count = Int(size) / MemoryLayout<T>.stride
        let pointer = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<T>.alignment)
        defer { pointer.deallocate() }
        guard AudioObjectGetPropertyData(object, &a, 0, nil, &size, pointer) == noErr else { return [] }
        let typed = pointer.bindMemory(to: T.self, capacity: count)
        return Array(UnsafeBufferPointer(start: typed, count: Int(size) / MemoryLayout<T>.stride))
    }

    static func string(_ object: AudioObjectID, _ addr: AudioObjectPropertyAddress) -> String? {
        var a = addr
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = withUnsafeMutablePointer(to: &value) {
            AudioObjectGetPropertyData(object, &a, 0, nil, &size, $0)
        }
        guard status == noErr, let value else { return nil }
        return value.takeRetainedValue() as String
    }
}

/// Saída de áudio (alto-falantes, fones, AirPods, HDMI…).
struct AudioOutputDevice: Identifiable, Hashable {
    let id: AudioObjectID
    let uid: String
    let name: String
    let transport: UInt32

    var symbol: String {
        let lower = name.lowercased()
        if lower.contains("airpods max") { return "airpodsmax" }
        if lower.contains("airpods pro") { return "airpodspro" }
        if lower.contains("airpods") { return "airpods" }
        switch transport {
        case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE: return "headphones"
        case kAudioDeviceTransportTypeHDMI, kAudioDeviceTransportTypeDisplayPort: return "tv"
        case kAudioDeviceTransportTypeAirPlay: return "airplayaudio"
        case kAudioDeviceTransportTypeUSB: return "hifispeaker"
        case kAudioDeviceTransportTypeBuiltIn:
            return lower.contains("fone") || lower.contains("headphone") ? "headphones" : "laptopcomputer"
        default: return "speaker.wave.2.fill"
        }
    }
}

enum AudioOutputs {
    static func all() -> [AudioOutputDevice] {
        CA.array(CA.system, CA.address(kAudioHardwarePropertyDevices), of: AudioObjectID.self).compactMap { id in
            var addr = CA.address(kAudioDevicePropertyStreamConfiguration, kAudioDevicePropertyScopeOutput)
            var size: UInt32 = 0
            guard AudioObjectGetPropertyDataSize(id, &addr, 0, nil, &size) == noErr, size > 0 else { return nil }
            let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
            defer { raw.deallocate() }
            guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, raw) == noErr else { return nil }
            let list = UnsafeMutableAudioBufferListPointer(raw.assumingMemoryBound(to: AudioBufferList.self))
            let channels = list.reduce(0) { $0 + Int($1.mNumberChannels) }
            guard channels > 0 else { return nil }
            guard let uid = CA.string(id, CA.address(kAudioDevicePropertyDeviceUID)) else { return nil }
            // Esconde agregados internos (inclusive os do próprio Alterna).
            if uid.hasPrefix("app.alterna.") { return nil }
            let name = CA.string(id, CA.address(kAudioObjectPropertyName)) ?? uid
            let transport = CA.get(id, CA.address(kAudioDevicePropertyTransportType), default: UInt32(0))
            return AudioOutputDevice(id: id, uid: uid, name: name, transport: transport)
        }
    }

    static var defaultID: AudioObjectID {
        CA.get(CA.system, CA.address(kAudioHardwarePropertyDefaultOutputDevice), default: AudioObjectID(kAudioObjectUnknown))
    }

    static func setDefault(_ id: AudioObjectID) {
        CA.set(CA.system, CA.address(kAudioHardwarePropertyDefaultOutputDevice), id)
        CA.set(CA.system, CA.address(kAudioHardwarePropertyDefaultSystemOutputDevice), id)
    }

    static func uid(of id: AudioObjectID) -> String? {
        CA.string(id, CA.address(kAudioDevicePropertyDeviceUID))
    }

    // Volume geral da saída (o mesmo da barra de menus).
    private static let mainVolume = CA.address(kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
                                               kAudioDevicePropertyScopeOutput)
    private static let mute = CA.address(kAudioDevicePropertyMute, kAudioDevicePropertyScopeOutput)

    static func volume(of id: AudioObjectID) -> Float? {
        if CA.has(id, mainVolume) { return CA.get(id, mainVolume, default: Float(0)) }
        let ch1 = CA.address(kAudioDevicePropertyVolumeScalar, kAudioDevicePropertyScopeOutput, 1)
        return CA.has(id, ch1) ? CA.get(id, ch1, default: Float(0)) : nil
    }

    static func setVolume(_ value: Float, of id: AudioObjectID) {
        let v = min(max(value, 0), 1)
        if CA.has(id, mainVolume) {
            CA.set(id, mainVolume, v)
        } else {
            for ch: UInt32 in [1, 2] {
                CA.set(id, CA.address(kAudioDevicePropertyVolumeScalar, kAudioDevicePropertyScopeOutput, ch), v)
            }
        }
    }

    static func isMuted(_ id: AudioObjectID) -> Bool {
        CA.has(id, mute) && CA.get(id, mute, default: UInt32(0)) != 0
    }

    static func setMuted(_ muted: Bool, _ id: AudioObjectID) {
        if CA.has(id, mute) { CA.set(id, mute, UInt32(muted ? 1 : 0)) }
    }

    static func canChangeVolume(_ id: AudioObjectID) -> Bool {
        CA.isSettable(id, mainVolume)
            || CA.isSettable(id, CA.address(kAudioDevicePropertyVolumeScalar, kAudioDevicePropertyScopeOutput, 1))
    }
}
