import Accelerate
import AVFoundation
import IOKit
import AudioToolbox
import CoreAudio

/// Microfone usado pelo comando de voz.
///
/// Usa sempre o microfone embutido do Mac quando existe. Assim, ao conectar um fone
/// Bluetooth (AirPods etc.), o macOS não troca o fone para o modo de chamada
/// (que piora o som) e o áudio do Alterna não "quebra" no meio da troca de aparelho.
enum AudioInput {
    /// Cria um AVAudioEngine novo. Um engine novo a cada sessão evita usar um formato
    /// de áudio antigo depois que um fone conecta ou desconecta (isso fechava o app).
    static func makeEngine(preferBuiltIn: Bool = true) -> AVAudioEngine {
        let engine = AVAudioEngine()
        if var device = chosenDevice(preferBuiltIn: preferBuiltIn), let unit = engine.inputNode.audioUnit {
            AudioUnitSetProperty(unit,
                                 kAudioOutputUnitProperty_CurrentDevice,
                                 kAudioUnitScope_Global,
                                 0,
                                 &device,
                                 UInt32(MemoryLayout<AudioDeviceID>.size))
        }
        return engine
    }

    /// O formato atual do microfone é válido (há microfone e ele está pronto)?
    static func isUsable(_ engine: AVAudioEngine) -> Bool {
        let format = engine.inputNode.outputFormat(forBus: 0)
        return format.sampleRate > 0 && format.channelCount > 0
    }

    /// Formato para o tap do microfone. Depois de trocar o aparelho para o microfone embutido,
    /// o AVAudioEngine ainda guarda a taxa do microfone padrão (ex.: AirPods a 48 kHz e o embutido
    /// a 44,1 kHz). Com `format: nil` o engine falha ao iniciar (erro -10868). Usar o formato real
    /// do hardware evita isso.
    static func tapFormat(_ engine: AVAudioEngine) -> AVAudioFormat? {
        let hardware = engine.inputNode.inputFormat(forBus: 0)
        guard hardware.sampleRate > 0, hardware.channelCount > 0 else { return nil }
        return hardware
    }

    /// Microfone escolhido em Ajustes › Comando de voz: "auto", "default" ou o UID de um aparelho.
    static var setting: String { UserDefaults.standard.string(forKey: "voice.microphone") ?? "auto" }

    /// Aparelho a usar. nil = microfone padrão do sistema.
    /// No automático, usa o microfone do Mac, menos com a tampa fechada (aí ele só entrega silêncio).
    static func chosenDevice(preferBuiltIn: Bool) -> AudioDeviceID? {
        switch setting {
        case "default": return nil
        case "auto": return preferBuiltIn && !isLidClosed ? builtInMicrophone() : nil
        default: return inputDevices().first { $0.uid == setting }?.id
        }
    }

    /// Nome do microfone que a sessão vai usar (para o diagnóstico).
    static func describeChoice(preferBuiltIn: Bool) -> String {
        if let id = chosenDevice(preferBuiltIn: preferBuiltIn) {
            return inputDevices().first { $0.id == id }?.name ?? "Microfone do Mac"
        }
        let defaultID = CA.get(CA.system, CA.address(kAudioHardwarePropertyDefaultInputDevice), default: AudioDeviceID(0))
        let name = inputDevices().first { $0.id == defaultID }?.name
        return "Padrão do sistema" + (name.map { " (\($0))" } ?? "")
    }

    /// MacBook com a tampa fechada (usando monitor externo).
    static var isLidClosed: Bool {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard service != 0 else { return false }
        defer { IOObjectRelease(service) }
        let value = IORegistryEntryCreateCFProperty(service, "AppleClamshellState" as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue()
        return (value as? Bool) ?? false
    }

    struct Device: Identifiable, Hashable {
        let id: AudioDeviceID
        let uid: String
        let name: String
    }

    /// Microfones disponíveis.
    static func inputDevices() -> [Device] {
        CA.array(CA.system, CA.address(kAudioHardwarePropertyDevices), of: AudioDeviceID.self).compactMap { id in
            let streams = CA.array(id, CA.address(kAudioDevicePropertyStreams, kAudioObjectPropertyScopeInput),
                                   of: AudioStreamID.self)
            guard !streams.isEmpty, let uid = CA.string(id, CA.address(kAudioDevicePropertyDeviceUID)),
                  !uid.hasPrefix("app.alterna."), !uid.hasPrefix("CADefaultDeviceAggregate") else { return nil }
            let name = CA.string(id, CA.address(kAudioObjectPropertyName)) ?? uid
            return Device(id: id, uid: uid, name: name)
        }
    }

    /// Maior amplitude do trecho (0 = silêncio digital, típico de microfone desligado).
    static func peak(_ buffer: AVAudioPCMBuffer) -> Float {
        guard let data = buffer.floatChannelData, buffer.frameLength > 0 else { return 0 }
        var value: Float = 0
        vDSP_maxmgv(data[0], 1, &value, vDSP_Length(buffer.frameLength))
        return value
    }

    static func builtInMicrophone() -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        let system = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr, size > 0 else { return nil }
        var devices = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &devices) == noErr else { return nil }

        for device in devices {
            var transport: UInt32 = 0
            var transportSize = UInt32(MemoryLayout<UInt32>.size)
            var transportAddress = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyTransportType,
                                                              mScope: kAudioObjectPropertyScopeGlobal,
                                                              mElement: kAudioObjectPropertyElementMain)
            guard AudioObjectGetPropertyData(device, &transportAddress, 0, nil, &transportSize, &transport) == noErr,
                  transport == kAudioDeviceTransportTypeBuiltIn else { continue }

            var streamsAddress = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreams,
                                                            mScope: kAudioObjectPropertyScopeInput,
                                                            mElement: kAudioObjectPropertyElementMain)
            var streamsSize: UInt32 = 0
            if AudioObjectGetPropertyDataSize(device, &streamsAddress, 0, nil, &streamsSize) == noErr, streamsSize > 0 {
                return device
            }
        }
        return nil
    }
}

/// Marca se o microfone já entregou áudio nesta sessão (escrito na thread de áudio).
final class AudioFlag: @unchecked Sendable {
    var received = false
    /// Maior amplitude ouvida. Fica em 0 quando o microfone só entrega silêncio.
    var peak: Float = 0

    func note(_ buffer: AVAudioPCMBuffer) {
        received = true
        if peak < 1e-5 { peak = max(peak, AudioInput.peak(buffer)) }
    }

    /// Recebeu áudio, mas só silêncio digital (ex.: microfone do MacBook com a tampa fechada).
    var onlySilence: Bool { received && peak < 1e-6 }
}
