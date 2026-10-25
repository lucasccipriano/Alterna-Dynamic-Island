import AVFoundation
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
        if preferBuiltIn, var device = builtInMicrophone(), let unit = engine.inputNode.audioUnit {
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
}
