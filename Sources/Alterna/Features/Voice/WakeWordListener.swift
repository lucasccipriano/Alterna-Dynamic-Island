import AVFoundation
import AppKit
import IOKit.ps
import Speech
import os

let voiceLog = Logger(subsystem: "app.alterna", category: "voz")

/// Fica ouvindo a palavra de ativação ("Alt") e executa o comando dito em seguida:
///   "Alt, abrir navegador"   "Alt… pesquisar contrato"   "Alt, bateria"
///
/// O reconhecimento roda no próprio Mac quando o idioma permite (nada vai para a internet).
/// Enquanto estiver ligado, o macOS mostra o ponto laranja do microfone na barra de menus.
@MainActor
final class WakeWordListener: ObservableObject {
    static let shared = WakeWordListener()

    enum State: Equatable {
        case off            // desligado nos Ajustes
        case paused         // pausado (na bateria, ou o botão de voz está em uso)
        case waiting        // ouvindo só a palavra de ativação
        case capturing      // ouviu "Alt": capturando o comando
        case running        // executando o comando
    }

    @Published private(set) var state: State = .off
    /// O comando que está sendo falado depois da palavra de ativação.
    @Published private(set) var command = ""
    @Published private(set) var errorMessage: String?
    /// Informações para os Ajustes (diagnóstico do microfone e da fala).
    @Published private(set) var lastHeard = ""
    @Published private(set) var audioReceived = false
    @Published private(set) var usingBuiltInMic = true
    @Published private(set) var microphoneName = ""
    /// O microfone entregou só silêncio (tampa fechada, microfone mudo…).
    @Published private(set) var silentMicrophone = false
    @Published private(set) var onDevice = false
    @Published private(set) var lastRecognitionError: String?

    private var preferBuiltIn = true
    private var startedAt = Date.distantPast

    private var engine = AVAudioEngine()
    private var configObserver: NSObjectProtocol?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var sessionTimer: Timer?
    private var silenceTimer: Timer?
    private var powerTimer: Timer?
    private var suspended = false
    private var sessionID = 0

    private init() {}

    var isActive: Bool { state != .off && state != .paused }

    // MARK: - Ligar e desligar

    /// Aplica os Ajustes (ligado/desligado, só na tomada).
    func applySettings() {
        let settings = AppSettings.shared
        powerTimer?.invalidate()
        powerTimer = nil

        guard settings.wakeWordEnabled, settings.isEnabled(.voice) else {
            stopSession()
            state = .off
            return
        }
        if settings.wakeWordOnlyOnPower {
            powerTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.checkPower() }
            }
        }
        if suspended || (settings.wakeWordOnlyOnPower && Self.isOnBattery) {
            stopSession()
            state = .paused
            return
        }
        guard task == nil else { return }
        Task {
            guard await VoiceController.requestPermissions() else {
                errorMessage = "Permita o Microfone e o Reconhecimento de Fala para o Alterna em Ajustes do Sistema › Privacidade e Segurança."
                state = .paused
                return
            }
            startSession()
        }
    }

    /// Botão "Reiniciar escuta" do diagnóstico.
    func restartNow() {
        preferBuiltIn = true
        errorMessage = nil
        lastRecognitionError = nil
        stopSession()
        state = AppSettings.shared.wakeWordEnabled ? .paused : .off
        applySettings()
    }

    /// Pausa enquanto o botão de voz usa o microfone.
    func suspend() {
        suspended = true
        stopSession()
        if state != .off { state = .paused }
    }

    func resumeSoon() {
        guard suspended else { return }
        suspended = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            self?.applySettings()
        }
    }

    private func checkPower() {
        let settings = AppSettings.shared
        let shouldRun = settings.wakeWordEnabled && settings.isEnabled(.voice) && !suspended && !(settings.wakeWordOnlyOnPower && Self.isOnBattery)
        if shouldRun && state == .paused { applySettings() }
        if !shouldRun && isActive && state == .waiting { stopSession(); state = .paused }
    }

    // MARK: - Sessão de reconhecimento

    private func startSession() {
        stopSession()
        let locale = Locale(identifier: AppSettings.shared.voiceLocale)
        guard let recognizer = SFSpeechRecognizer(locale: locale), recognizer.isAvailable else {
            errorMessage = "O reconhecimento de fala não está disponível para este idioma agora."
            state = .paused
            return
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        onDevice = recognizer.supportsOnDeviceRecognition
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }
        request.contextualStrings = [AppSettings.shared.wakeWord, "abrir", "pesquisar", "tocar"]
        self.request = request

        engine = AudioInput.makeEngine(preferBuiltIn: preferBuiltIn)
        usingBuiltInMic = AudioInput.chosenDevice(preferBuiltIn: preferBuiltIn) != nil
        microphoneName = AudioInput.describeChoice(preferBuiltIn: preferBuiltIn)
        guard AudioInput.isUsable(engine) else {
            errorMessage = "Nenhum microfone encontrado."
            state = .paused
            return
        }
        let input = engine.inputNode
        input.removeTap(onBus: 0)
        // Usa o formato real do microfone escolhido (ver AudioInput.tapFormat).
        let flag = AudioFlag()
        input.installTap(onBus: 0, bufferSize: 1024, format: AudioInput.tapFormat(engine)) { [weak request] buffer, _ in
            request?.append(buffer)
            flag.note(buffer)
        }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            // O microfone embutido falhou: tenta o microfone padrão do sistema antes de desistir.
            if preferBuiltIn {
                preferBuiltIn = false
                restartAfterDelay(0.3)
                return
            }
            errorMessage = "Não consegui usar o microfone: \(error.localizedDescription)"
            state = .paused
            return
        }

        errorMessage = nil
        command = ""
        state = .waiting
        sessionID += 1
        let id = sessionID
        startedAt = Date()
        audioReceived = false
        observeConfigurationChanges()

        // Se o microfone embutido não entregar áudio, tenta o microfone padrão do sistema.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
            guard let self, self.sessionID == id else { return }
            self.audioReceived = flag.received
            self.silentMicrophone = flag.onlySilence
            let broken = !flag.received || flag.onlySilence
            if broken && self.preferBuiltIn && AudioInput.setting == "auto" {
                // Microfone do Mac sem som: passa para o microfone padrão do sistema.
                self.preferBuiltIn = false
                self.restartAfterDelay(0.3)
            } else if flag.onlySilence {
                self.errorMessage = "O microfone escolhido só está entregando silêncio. Escolha outro em Ajustes › Comando de voz › Microfone."
            } else if !flag.received {
                self.errorMessage = "O microfone não está entregando áudio. Confira a permissão de Microfone."
            }
        }

        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            let text = result?.bestTranscription.formattedString ?? ""
            let isFinal = result?.isFinal ?? false
            let failed = error != nil
            let errorText = error.map { "\(($0 as NSError).domain) \(($0 as NSError).code): \($0.localizedDescription)" }
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self, self.sessionID == id else { return }
                    if let errorText { self.lastRecognitionError = errorText }
                    if !text.isEmpty { self.lastHeard = String(text.suffix(80)) }
                    self.handle(text: text, isFinal: isFinal, failed: failed)
                }
            }
        }

        // O reconhecimento contínuo tem limite de tempo: recomeça a sessão de tempos em tempos.
        sessionTimer = Timer.scheduledTimer(withTimeInterval: 50, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.state == .waiting else { return }
                self.startSession()
            }
        }
    }

    /// Um fone conectou/desconectou: o áudio muda de formato. Recomeça a escuta com um engine novo.
    private func observeConfigurationChanges() {
        if let configObserver { NotificationCenter.default.removeObserver(configObserver) }
        configObserver = NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange,
                                                                object: engine, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                // Trocar o microfone no início da sessão também gera este aviso: ignora os primeiros segundos.
                guard Date().timeIntervalSince(self.startedAt) > 2.5 else { return }
                if self.state == .capturing {
                    self.finishCapture()
                } else if self.state == .waiting {
                    self.restartAfterDelay(1)
                }
            }
        }
    }

    private func stopSession() {
        sessionID += 1
        sessionTimer?.invalidate(); sessionTimer = nil
        silenceTimer?.invalidate(); silenceTimer = nil
        if engine.isRunning { engine.stop() }
        engine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.cancel()
        task = nil
        request = nil
    }

    private func restartAfterDelay(_ seconds: TimeInterval = 0.4) {
        stopSession()
        guard AppSettings.shared.wakeWordEnabled, !suspended else { return }
        state = .paused
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
            self?.applySettings()
        }
    }

    // MARK: - Palavra de ativação e comando

    private func handle(text: String, isFinal: Bool, failed: Bool) {
        voiceLog.notice("ouviu [\(String(describing: self.state), privacy: .public)] final=\(isFinal) erro=\(failed): \(text, privacy: .public)")
        let words = text.split(whereSeparator: \.isWhitespace).map(String.init)
        let folded = words.map(CommandEngine.fold)

        if state == .waiting, let index = wakeIndex(in: folded) {
            state = .capturing
            NSSound(named: "Tink")?.play()
            IslandController.shared.showListeningPreview()
            command = words[(index + 1)...].joined(separator: " ")
            restartSilence(after: command.isEmpty ? 5 : 1.4)
        } else if state == .capturing {
            // Depois de uma pausa o reconhecimento recomeça a frase sem o "Alt"
            // (ex.: "Alt" … "Abrir calculadora"): aí o texto inteiro é o comando.
            let newCommand: String
            if let index = wakeIndex(in: folded) {
                newCommand = words[(index + 1)...].joined(separator: " ")
            } else if command.isEmpty, folded.count == 1,
                      ["al", "au", "ou", "ha", "ol"].contains(where: { folded[0].hasPrefix($0) }) {
                // Ainda é o reconhecimento revisando a própria palavra "Alt" (ex.: "Alta").
                newCommand = ""
            } else {
                newCommand = words.joined(separator: " ")
            }
            if !newCommand.isEmpty, newCommand != command {
                command = newCommand
                restartSilence(after: 1.4)
            }
        }

        if isFinal || failed {
            if state == .capturing {
                finishCapture()
            } else if state == .waiting {
                restartAfterDelay(failed ? 1 : 0.2)
            }
        }
    }

    /// Posição da última vez que a palavra de ativação aparece.
    private func wakeIndex(in folded: [String]) -> Int? {
        let variants = Self.variants(of: AppSettings.shared.wakeWord)
        return folded.lastIndex { variants.contains($0) }
    }

    /// "Alt" pode ser transcrito de jeitos parecidos.
    static func variants(of word: String) -> Set<String> {
        let base = CommandEngine.fold(word)
        guard !base.isEmpty else { return [] }
        var set: Set<String> = [base, base + "e", base + "s", "h" + base, base + "h"]
        if base == "alt" { set.formUnion(["alti", "olt", "aut", "halt", "alto", "auto", "out", "aldo"]) }
        return set
    }

    private func restartSilence(after seconds: TimeInterval) {
        silenceTimer?.invalidate()
        silenceTimer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.finishCapture() }
        }
    }

    private func finishCapture() {
        guard state == .capturing else { return }
        let text = command.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        stopSession()

        guard !text.isEmpty else {
            voiceLog.notice("captura terminou sem comando")
            // Disse só "Alt" e não falou mais nada.
            command = ""
            IslandController.shared.endListeningPreview(result: nil)
            restartAfterDelay()
            return
        }

        state = .running
        voiceLog.notice("executando comando: \(text, privacy: .public)")
        VoiceController.shared.run(text) { [weak self] result in
            voiceLog.notice("resultado: \(String(describing: result), privacy: .public)")
            IslandController.shared.endListeningPreview(result: result)
            self?.command = ""
            self?.restartAfterDelay(0.8)
        }
    }

    // MARK: - Energia

    static var isOnBattery: Bool {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let type = IOPSGetProvidingPowerSourceType(blob)?.takeUnretainedValue() else { return false }
        return (type as String) == "Battery Power"
    }
}

// MARK: - Resumo do resultado (para o banner)

extension CommandResult {
    var banner: (symbol: String, title: String, subtitle: String) {
        switch self {
        case .opened(let name, _, let detail): ("checkmark.circle.fill", name, detail)
        case .info(let symbol, let title, let value, let detail): (symbol, "\(title): \(value)", detail ?? "")
        case .music(let title, let detail): ("music.note", title, detail)
        case .message(let symbol, let title, let detail, _): (symbol, title, detail)
        case .items(let title, let items, _): ("magnifyingglass", title, "\(items.count) resultado(s)")
        }
    }

    /// Resultados com lista precisam da ilha aberta para escolher.
    var needsExpandedView: Bool {
        if case .items = self { return true }
        if case .message(_, _, _, let web) = self, web != nil { return true }
        return false
    }
}
