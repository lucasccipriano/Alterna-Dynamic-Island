import AppKit
import CoreAudio
import Darwin

/// Ajuste salvo de um app: volume, mudo e saída de áudio.
struct AppSoundRule: Codable, Equatable {
    var volume: Float = 1
    var muted = false
    /// nil = segue a saída padrão do Mac.
    var outputUID: String?

    var isDefault: Bool { volume >= 0.999 && !muted && outputUID == nil }
}

/// Um app (ou serviço) que usa o áudio do Mac. Junta os processos auxiliares
/// (ex.: "Google Chrome Helper") no app principal.
struct AudioApp: Identifiable, Equatable {
    let id: String
    let name: String
    let bundleID: String?
    let path: String?
    var processes: [AudioObjectID]
    var isPlaying: Bool

    static func == (a: AudioApp, b: AudioApp) -> Bool {
        a.id == b.id && a.processes == b.processes && a.isPlaying == b.isPlaying && a.name == b.name
    }
}

/// Central de som: volume geral, saída e um mixer por app.
@MainActor
final class SoundMixer: ObservableObject {
    static let shared = SoundMixer()

    @Published private(set) var apps: [AudioApp] = []
    @Published private(set) var outputs: [AudioOutputDevice] = []
    @Published private(set) var defaultOutputID = AudioObjectID(kAudioObjectUnknown)
    @Published private(set) var masterVolume: Float = 0.5
    @Published private(set) var masterMuted = false
    @Published private(set) var canChangeMaster = true
    @Published private(set) var rules: [String: AppSoundRule] = [:]
    @Published private(set) var errorMessage: String?
    @Published private(set) var permissionDenied = false

    /// Process taps existem a partir do macOS 14.2.
    var supportsPerApp: Bool {
        if #available(macOS 14.2, *) { return true }
        return false
    }

    var defaultOutput: AudioOutputDevice? { outputs.first { $0.id == defaultOutputID } }
    var playingApps: [AudioApp] { apps.filter(\.isPlaying) }

    private var timer: Timer?
    private var taps: [String: AnyObject] = [:]
    private var appInfo: [pid_t: (key: String, name: String, bundleID: String?, path: String?)] = [:]
    private var lastPlayed: [String: Date] = [:]
    private var failed: [String: Date] = [:]
    private let ownPID = ProcessInfo.processInfo.processIdentifier

    private init() {
        if let data = UserDefaults.standard.data(forKey: "sound.rules"),
           let saved = try? JSONDecoder().decode([String: AppSoundRule].self, from: data) {
            rules = saved
        }
    }

    func start() {
        guard timer == nil else { return }
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        taps = [:]
        apps = []
    }

    // MARK: - Leitura

    func refresh() {
        let currentDefault = AudioOutputs.defaultID
        let devices = AudioOutputs.all()
        if devices != outputs { outputs = devices }
        if currentDefault != defaultOutputID { defaultOutputID = currentDefault }
        let volume = AudioOutputs.volume(of: currentDefault) ?? masterVolume
        if abs(volume - masterVolume) > 0.004 { masterVolume = volume }
        let muted = AudioOutputs.isMuted(currentDefault)
        if muted != masterMuted { masterMuted = muted }
        let canChange = AudioOutputs.canChangeVolume(currentDefault)
        if canChange != canChangeMaster { canChangeMaster = canChange }

        guard #available(macOS 14.2, *), timer != nil else { return }
        let found = readApps()
        if found != apps { apps = found }
        applyRules()
    }

    @available(macOS 14.2, *)
    private func readApps() -> [AudioApp] {
        let objects = CA.array(CA.system, CA.address(kAudioHardwarePropertyProcessObjectList), of: AudioObjectID.self)
        var grouped: [String: AudioApp] = [:]
        var order: [String] = []
        var alive = Set<pid_t>()
        let now = Date()

        for object in objects {
            let pid = CA.get(object, CA.address(kAudioProcessPropertyPID), default: pid_t(-1))
            guard pid > 0, pid != ownPID else { continue }
            alive.insert(pid)
            let info = appInfo[pid] ?? resolve(pid: pid, object: object)
            appInfo[pid] = info
            let running = CA.get(object, CA.address(kAudioProcessPropertyIsRunningOutput), default: UInt32(0)) != 0
            if running { lastPlayed[info.key] = now }

            if var app = grouped[info.key] {
                app.processes.append(object)
                app.isPlaying = app.isPlaying || running
                grouped[info.key] = app
            } else {
                grouped[info.key] = AudioApp(id: info.key, name: info.name, bundleID: info.bundleID, path: info.path,
                                             processes: [object], isPlaying: running)
                order.append(info.key)
            }
        }
        appInfo = appInfo.filter { alive.contains($0.key) }

        // Mostra quem toca agora, quem tocou há pouco (o som vai e volta entre faixas)
        // e quem tem um ajuste salvo e está aberto.
        return order.compactMap { key -> AudioApp? in
            guard var app = grouped[key] else { return nil }
            let recent = lastPlayed[key].map { now.timeIntervalSince($0) < 12 } ?? false
            let hasRule = !(rules[key]?.isDefault ?? true)
            guard app.isPlaying || recent || hasRule else { return nil }
            app.processes.sort()
            return app
        }
        .sorted { a, b in
            if a.isPlaying != b.isPlaying { return a.isPlaying }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
    }

    /// Descobre o app dono do processo: sobe no caminho até o primeiro ".app".
    private func resolve(pid: pid_t, object: AudioObjectID) -> (key: String, name: String, bundleID: String?, path: String?) {
        var buffer = [CChar](repeating: 0, count: 4096)
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        let executable = length > 0 ? String(cString: buffer) : ""
        let audioBundleID = CA.string(object, CA.address(kAudioProcessPropertyBundleID))

        if let range = executable.range(of: ".app/") {
            let appPath = String(executable[..<range.lowerBound]) + ".app"
            let bundle = Bundle(path: appPath)
            let bundleID = bundle?.bundleIdentifier ?? audioBundleID
            let name = (bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
                ?? (bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String)
                ?? FileManager.default.displayName(atPath: appPath).replacingOccurrences(of: ".app", with: "")
            return (bundleID ?? appPath, name, bundleID, appPath)
        }
        // Serviços do sistema (sem .app).
        let processName = (executable as NSString).lastPathComponent
        let name = Self.friendlyName(processName.isEmpty ? (audioBundleID ?? "Processo \(pid)") : processName)
        return (audioBundleID ?? "proc:\(processName)", name, audioBundleID, nil)
    }

    private static func friendlyName(_ raw: String) -> String {
        switch raw {
        case "coreaudiod", "systemsoundserverd": return "Sons do sistema"
        case "com.apple.WebKit.GPU": return "Safari (web)"
        default: return raw
        }
    }

    func icon(for app: AudioApp) -> NSImage {
        if let path = app.path { return NSWorkspace.shared.icon(forFile: path) }
        return NSImage(systemSymbolName: "gearshape.fill", accessibilityDescription: nil) ?? NSImage()
    }

    // MARK: - Volume geral

    func setMasterVolume(_ value: Float) {
        masterVolume = value
        AudioOutputs.setVolume(value, of: defaultOutputID)
        if value > 0, masterMuted { setMasterMuted(false) }
    }

    func setMasterMuted(_ muted: Bool) {
        masterMuted = muted
        AudioOutputs.setMuted(muted, defaultOutputID)
    }

    func setDefaultOutput(_ device: AudioOutputDevice) {
        AudioOutputs.setDefault(device.id)
        refresh()
    }

    // MARK: - Ajustes por app

    func rule(for app: AudioApp) -> AppSoundRule { rules[app.id] ?? AppSoundRule() }

    func setVolume(_ value: Float, for app: AudioApp) {
        update(app) { $0.volume = min(max(value, 0), 1); if value > 0.001 { $0.muted = false } }
    }

    func toggleMute(_ app: AudioApp) {
        update(app) { $0.muted.toggle() }
    }

    func setOutput(_ uid: String?, for app: AudioApp) {
        update(app) { $0.outputUID = uid }
    }

    func reset(_ app: AudioApp) {
        update(app) { $0 = AppSoundRule() }
    }

    func reset(key: String) {
        rules[key] = nil
        persist()
        applyRules()
    }

    func resetAll() {
        rules = [:]
        persist()
        applyRules()
    }

    private func update(_ app: AudioApp, _ change: (inout AppSoundRule) -> Void) {
        var rule = rules[app.id] ?? AppSoundRule()
        change(&rule)
        rules[app.id] = rule.isDefault ? nil : rule
        persist()
        // Volume muda direto no tap ativo, sem recriar nada.
        if #available(macOS 14.2, *), let tap = taps[app.id] as? AppAudioTap,
           tap.outputUID == resolvedOutputUID(rule) {
            tap.gain.target = rule.muted ? 0 : rule.volume
        }
        applyRules()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(rules) {
            UserDefaults.standard.set(data, forKey: "sound.rules")
        }
    }

    private func resolvedOutputUID(_ rule: AppSoundRule) -> String? {
        if let uid = rule.outputUID, outputs.contains(where: { $0.uid == uid }) { return uid }
        return AudioOutputs.uid(of: defaultOutputID)
    }

    /// Cria, ajusta ou remove os taps para bater com os ajustes salvos.
    private func applyRules() {
        guard #available(macOS 14.2, *) else { return }
        var wanted = Set<String>()
        for app in apps {
            guard let rule = rules[app.id], !rule.isDefault, let uid = resolvedOutputUID(rule) else { continue }
            wanted.insert(app.id)
            let volume = rule.muted ? 0 : rule.volume
            if let tap = taps[app.id] as? AppAudioTap, tap.processes == app.processes, tap.outputUID == uid {
                tap.gain.target = volume
                continue
            }
            // Depois de uma falha, espera um pouco antes de tentar de novo.
            if let failedAt = failed[app.id], Date().timeIntervalSince(failedAt) < 5 { continue }
            taps[app.id] = nil
            do {
                taps[app.id] = try AppAudioTap(processes: app.processes, outputUID: uid, volume: volume)
                failed[app.id] = nil
                if errorMessage != nil { errorMessage = nil }
                if permissionDenied { permissionDenied = false }
            } catch {
                failed[app.id] = Date()
                errorMessage = "Não deu para ajustar o som de \(app.name). Permita “Gravação de áudio do sistema” para o Alterna."
                permissionDenied = true
            }
        }
        for key in taps.keys where !wanted.contains(key) { taps[key] = nil }
    }

    func openPrivacySettings() {
        SettingsOpener.openSystemSettings("com.apple.preference.security?Privacy_AudioCapture")
    }
}
