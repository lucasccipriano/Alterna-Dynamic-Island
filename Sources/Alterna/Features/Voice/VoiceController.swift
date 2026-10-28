import AVFoundation
import AppKit
import Speech

/// Ouve um comando de voz com o reconhecimento de fala da Apple e executa.
@MainActor
final class VoiceController: ObservableObject {
    static let shared = VoiceController()

    @Published private(set) var isListening = false
    @Published private(set) var isWorking = false
    @Published private(set) var transcript = ""
    @Published private(set) var result: CommandResult?
    @Published private(set) var level: Float = 0
    @Published private(set) var errorMessage: String?

    private var engine = AVAudioEngine()
    private var configObserver: NSObjectProtocol?
    private var preferBuiltIn = true
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var silenceTimer: Timer?
    private var commandTask: Task<Void, Never>?

    private init() {}

    func toggle() {
        isListening ? finishListening() : startListening()
    }

    // MARK: - Ouvir

    func startListening() {
        guard !isListening else { return }
        errorMessage = nil
        result = nil
        transcript = ""

        // O microfone do "Alt" pausa enquanto você fala pelo botão ou atalho.
        WakeWordListener.shared.suspend()
        Task {
            guard await Self.requestPermissions() else {
                WakeWordListener.shared.resumeSoon()
                errorMessage = "Permita o Microfone e o Reconhecimento de Fala para o Alterna em Ajustes do Sistema › Privacidade e Segurança."
                IslandModel.shared.keepOpen = false
                return
            }
            beginSession()
        }
    }

    private func beginSession() {
        let locale = Locale(identifier: AppSettings.shared.voiceLocale)
        guard let recognizer = SFSpeechRecognizer(locale: locale), recognizer.isAvailable else {
            errorMessage = "O reconhecimento de fala não está disponível para este idioma agora."
            WakeWordListener.shared.resumeSoon()
            return
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }
        request.contextualStrings = ["abrir", "pesquisar", "pesquisar na internet", "tocar", "bateria", "armazenamento"]
        self.request = request

        engine = AudioInput.makeEngine(preferBuiltIn: preferBuiltIn)
        let startedAt = Date()
        if let configObserver { NotificationCenter.default.removeObserver(configObserver) }
        // Se um fone conectar/desconectar enquanto ouve, encerra com o que já foi dito.
        // (Trocar o microfone no início também gera o aviso: ignora os primeiros segundos.)
        configObserver = NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange,
                                                                object: engine, queue: .main) { _ in
            Task { @MainActor in
                guard Date().timeIntervalSince(startedAt) > 2.5 else { return }
                VoiceController.shared.finishListening()
            }
        }
        let input = engine.inputNode
        guard AudioInput.isUsable(engine) else {
            errorMessage = "Nenhum microfone encontrado."
            WakeWordListener.shared.resumeSoon()
            return
        }
        input.removeTap(onBus: 0)
        let flag = AudioFlag()
        input.installTap(onBus: 0, bufferSize: 1024, format: AudioInput.tapFormat(engine)) { [weak request] buffer, _ in
            request?.append(buffer)
            flag.received = true
            let level = Self.rms(buffer)
            DispatchQueue.main.async {
                MainActor.assumeIsolated { VoiceController.shared.level = level }
            }
        }

        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            // O microfone embutido falhou: tenta o microfone padrão do sistema.
            if preferBuiltIn {
                preferBuiltIn = false
                beginSession()
                return
            }
            errorMessage = "Não consegui usar o microfone: \(error.localizedDescription)"
            WakeWordListener.shared.resumeSoon()
            return
        }

        isListening = true
        IslandModel.shared.keepOpen = true

        // Microfone embutido sem áudio: tenta de novo com o microfone padrão.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            guard let self, self.isListening, !flag.received else { return }
            if self.preferBuiltIn {
                self.preferBuiltIn = false
                self.stopAudio()
                self.startListening()
            } else {
                self.stopAudio()
                self.errorMessage = "O microfone não está entregando áudio. Confira a permissão de Microfone."
            }
        }
        restartSilenceTimer(after: 6) // tempo para começar a falar

        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            let text = result?.bestTranscription.formattedString
            let isFinal = result?.isFinal ?? false
            let failed = error != nil
            let errorText = error.map { "\(($0 as NSError).domain) \(($0 as NSError).code)" }
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self, self.isListening else { return }
                    if let text, !text.isEmpty {
                        self.transcript = text
                        self.restartSilenceTimer(after: 1.4)
                    }
                    if isFinal || (failed && !self.transcript.isEmpty) {
                        self.finishListening()
                    } else if failed {
                        self.stopAudio()
                        self.errorMessage = "Não entendi. Tente de novo." + (errorText.map { " (\($0))" } ?? "")
                    }
                }
            }
        }
    }

    /// Para de ouvir e executa o que foi dito.
    func finishListening() {
        guard isListening else { return }
        stopAudio()
        let text = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty {
            errorMessage = "Não ouvi nada. Toque na esfera e fale um comando."
        } else {
            run(text)
        }
    }

    func cancel() {
        stopAudio()
        transcript = ""
    }

    private func stopAudio() {
        silenceTimer?.invalidate()
        silenceTimer = nil
        if engine.isRunning { engine.stop() }
        engine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.cancel()
        task = nil
        request = nil
        isListening = false
        level = 0
        WakeWordListener.shared.resumeSoon()
    }

    private func restartSilenceTimer(after seconds: TimeInterval) {
        silenceTimer?.invalidate()
        silenceTimer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.finishListening() }
        }
    }

    // MARK: - Executar

    func run(_ text: String, completion: ((CommandResult) -> Void)? = nil) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        transcript = trimmed
        errorMessage = nil
        isWorking = true
        commandTask?.cancel()
        commandTask = Task {
            let outcome = await CommandEngine.execute(trimmed)
            guard !Task.isCancelled else { return }
            result = outcome
            isWorking = false
            IslandModel.shared.keepOpen = false
            completion?(outcome)
        }
    }

    func clear() {
        result = nil
        transcript = ""
        errorMessage = nil
    }

    // MARK: - Permissões

    static func requestPermissions() async -> Bool {
        let speech: Bool = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
        guard speech else { return false }
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .audio)
        default: return false
        }
    }

    nonisolated private static func rms(_ buffer: AVAudioPCMBuffer) -> Float {
        guard let data = buffer.floatChannelData?[0] else { return 0 }
        let count = Int(buffer.frameLength)
        guard count > 0 else { return 0 }
        var sum: Float = 0
        for i in 0..<count { sum += data[i] * data[i] }
        let rms = sqrt(sum / Float(count))
        return min(rms * 12, 1)
    }
}
