import AudioToolbox
import CoreAudio
import Foundation

/// Ganho compartilhado entre a interface e a thread de áudio.
/// Valores de 32 bits alinhados: leitura/escrita atômicas na prática, sem travas na thread de tempo real.
final class TapGain: @unchecked Sendable {
    var target: Float = 1
    private var current: Float = 1
    /// Quantos canais do fim da lista de entrada pertencem ao tap.
    var tapChannels = 2

    init(_ value: Float) { target = value; current = value }

    /// Copia o áudio capturado do app para a saída, aplicando o volume com uma rampa curta (sem estalos).
    func render(_ input: UnsafePointer<AudioBufferList>, _ output: UnsafeMutablePointer<AudioBufferList>) {
        let ins = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
        let outs = UnsafeMutableAudioBufferListPointer(output)

        for buffer in outs where buffer.mData != nil {
            memset(buffer.mData, 0, Int(buffer.mDataByteSize))
        }

        // Os canais do tap ficam no fim da lista (antes podem vir entradas do próprio dispositivo).
        var firstTapBuffer = ins.count
        var counted = 0
        while firstTapBuffer > 0 && counted < tapChannels {
            firstTapBuffer -= 1
            counted += Int(ins[firstTapBuffer].mNumberChannels)
        }
        guard counted > 0, firstTapBuffer < ins.count else { return }

        let firstIn = ins[firstTapBuffer]
        guard firstIn.mNumberChannels > 0 else { return }
        let inFrames = Int(firstIn.mDataByteSize) / (4 * Int(firstIn.mNumberChannels))

        let goal = target
        let start = current
        var outBase = 0
        for o in 0..<outs.count {
            let ob = outs[o]
            guard let od = ob.mData?.assumingMemoryBound(to: Float.self), ob.mNumberChannels > 0 else { continue }
            let oc = Int(ob.mNumberChannels)
            let frames = min(Int(ob.mDataByteSize) / (4 * oc), inFrames)
            guard frames > 0 else { outBase += oc; continue }
            let step = (goal - start) / Float(frames)

            for c in 0..<oc {
                // Canal de origem: repete os canais do tap (estéreo → mais canais, se precisar).
                var source = (outBase + c) % counted
                var bi = firstTapBuffer
                while bi < ins.count, source >= Int(ins[bi].mNumberChannels) {
                    source -= Int(ins[bi].mNumberChannels)
                    bi += 1
                }
                guard bi < ins.count, let id = ins[bi].mData?.assumingMemoryBound(to: Float.self) else { continue }
                let ic = Int(ins[bi].mNumberChannels)
                let available = Int(ins[bi].mDataByteSize) / (4 * ic)
                let n = min(frames, available)
                var g = start
                for f in 0..<n {
                    od[f * oc + c] = id[f * ic + source] * g
                    g += step
                }
            }
            outBase += oc
        }
        current = goal
    }
}

/// Captura o áudio de um app (process tap do macOS 14.2+), silencia o original
/// e toca de novo na saída escolhida, com o volume ajustado.
@available(macOS 14.2, *)
final class AppAudioTap {
    enum TapError: LocalizedError {
        case tap(OSStatus), aggregate(OSStatus), io(OSStatus)
        var errorDescription: String? {
            switch self {
            case .tap(let s): "Não foi possível capturar o áudio do app (\(s))."
            case .aggregate(let s): "Não foi possível preparar a saída de áudio (\(s))."
            case .io(let s): "Não foi possível tocar o áudio ajustado (\(s))."
            }
        }
    }

    let processes: [AudioObjectID]
    let outputUID: String
    let gain: TapGain

    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var procID: AudioDeviceIOProcID?
    private let queue = DispatchQueue(label: "app.alterna.sound.tap", qos: .userInteractive)

    init(processes: [AudioObjectID], outputUID: String, volume: Float) throws {
        self.processes = processes
        self.outputUID = outputUID
        self.gain = TapGain(volume)

        let description = CATapDescription(stereoMixdownOfProcesses: processes)
        description.uuid = UUID()
        description.name = "Alterna"
        description.isPrivate = true
        description.muteBehavior = CATapMuteBehavior.mutedWhenTapped

        var status = AudioHardwareCreateProcessTap(description, &tapID)
        guard status == noErr else { throw TapError.tap(status) }

        let format = CA.get(tapID, CA.address(kAudioTapPropertyFormat), default: AudioStreamBasicDescription())
        if format.mChannelsPerFrame > 0 { gain.tapChannels = Int(format.mChannelsPerFrame) }

        let settings: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Alterna",
            kAudioAggregateDeviceUIDKey: "app.alterna.aggregate.\(UUID().uuidString)",
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outputUID]],
            kAudioAggregateDeviceTapListKey: [[
                kAudioSubTapDriftCompensationKey: true,
                kAudioSubTapUIDKey: description.uuid.uuidString
            ]]
        ]
        status = AudioHardwareCreateAggregateDevice(settings as CFDictionary, &aggregateID)
        guard status == noErr else { cleanup(); throw TapError.aggregate(status) }

        let gain = self.gain
        status = AudioDeviceCreateIOProcIDWithBlock(&procID, aggregateID, queue) { _, input, _, output, _ in
            gain.render(input, output)
        }
        guard status == noErr, let procID else { cleanup(); throw TapError.io(status) }

        status = AudioDeviceStart(aggregateID, procID)
        guard status == noErr else { cleanup(); throw TapError.io(status) }
    }

    deinit { cleanup() }

    private func cleanup() {
        if aggregateID != kAudioObjectUnknown {
            if let procID {
                AudioDeviceStop(aggregateID, procID)
                AudioDeviceDestroyIOProcID(aggregateID, procID)
            }
            AudioHardwareDestroyAggregateDevice(aggregateID)
            aggregateID = AudioObjectID(kAudioObjectUnknown)
        }
        procID = nil
        if tapID != kAudioObjectUnknown {
            AudioHardwareDestroyProcessTap(tapID)
            tapID = AudioObjectID(kAudioObjectUnknown)
        }
    }
}
