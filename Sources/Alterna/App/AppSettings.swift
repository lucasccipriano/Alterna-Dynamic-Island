import AppKit
import Combine
import SwiftUI

/// Preferências gerais do app (a ilha, atalhos do app e voz).
@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    /// Funcionalidades ligadas. Por padrão só Música e Notificações.
    @Published private(set) var enabledFeatures: Set<Feature>

    func isEnabled(_ feature: Feature) -> Bool {
        feature == .profiles ? ProfileStore.shared.profilesEnabled : enabledFeatures.contains(feature)
    }

    func setEnabled(_ feature: Feature, _ on: Bool) {
        if feature == .profiles {
            ProfileStore.shared.profilesEnabled = on
        }
        if on { enabledFeatures.insert(feature) } else { enabledFeatures.remove(feature) }
        defaults.set(on, forKey: feature.defaultsKey)
        apply(feature)
    }

    func binding(_ feature: Feature) -> Binding<Bool> {
        Binding(get: { self.isEnabled(feature) }, set: { self.setEnabled(feature, $0) })
    }

    /// Liga ou desliga o serviço por trás da funcionalidade.
    func apply(_ feature: Feature) {
        let on = isEnabled(feature)
        switch feature {
        case .music: on ? SpotifyController.shared.start() : SpotifyController.shared.stop()
        case .notifications: on ? NotificationMonitor.shared.start() : NotificationMonitor.shared.stop()
        case .voice:
            WakeWordListener.shared.applySettings()
            registerHotKeys()
            if !on { VoiceController.shared.cancel() }
        case .profiles: break
        case .bluetooth: if on { BluetoothManager.shared.activate() }
        case .sound: on ? SoundMixer.shared.start() : SoundMixer.shared.stop()
        }
    }

    @Published var showIsland: Bool {
        didSet { save(showIsland, Keys.showIsland); IslandController.shared.setVisible(showIsland) }
    }
    @Published var expandOnHover: Bool {
        didSet { save(expandOnHover, Keys.expandOnHover) }
    }
    /// Escuta contínua da palavra de ativação.
    @Published var wakeWordEnabled: Bool {
        didSet { save(wakeWordEnabled, "voice.wakeEnabled"); WakeWordListener.shared.applySettings() }
    }
    @Published var wakeWord: String {
        didSet { save(wakeWord, "voice.wakeWord") }
    }
    @Published var wakeWordOnlyOnPower: Bool {
        didSet { save(wakeWordOnlyOnPower, "voice.wakeOnlyOnPower"); WakeWordListener.shared.applySettings() }
    }
    @Published var islandTheme: IslandTheme {
        didSet { save(islandTheme.rawValue, "island.theme") }
    }
    @Published var invertMouseCarousel: Bool {
        didSet { save(invertMouseCarousel, "island.invertMouseCarousel") }
    }
    @Published var musicLiveActivity: Bool {
        didSet { save(musicLiveActivity, Keys.musicLive) }
    }
    /// "auto", "default" ou o UID de um microfone.
    @Published var voiceMicrophone: String {
        didSet { save(voiceMicrophone, "voice.microphone"); WakeWordListener.shared.restartNow() }
    }
    @Published var voiceLocale: String {
        didSet { save(voiceLocale, Keys.voiceLocale) }
    }
    @Published var voiceShortcut: Shortcut? {
        didSet { saveShortcut(voiceShortcut, Keys.voiceShortcut); registerHotKeys() }
    }
    @Published var islandShortcut: Shortcut? {
        didSet { saveShortcut(islandShortcut, Keys.islandShortcut); registerHotKeys() }
    }

    static let voiceLocales: [(id: String, name: String)] = [
        ("pt-BR", "Português (Brasil)"),
        ("pt-PT", "Português (Portugal)"),
        ("en-US", "Inglês (EUA)"),
        ("es-ES", "Espanhol (Espanha)")
    ]

    private enum Keys {
        static let showIsland = "island.show"
        static let expandOnHover = "island.expandOnHover"
        static let musicLive = "island.musicLiveActivity"
        static let voiceLocale = "voice.locale"
        static let voiceShortcut = "voice.shortcut"
        static let islandShortcut = "island.shortcut"
    }

    private let defaults = UserDefaults.standard

    private init() {
        let defaults = UserDefaults.standard
        enabledFeatures = Set(Feature.allCases.filter { feature in
            defaults.object(forKey: feature.defaultsKey) as? Bool ?? feature.onByDefault
        })
        showIsland = defaults.object(forKey: Keys.showIsland) as? Bool ?? true
        expandOnHover = defaults.object(forKey: Keys.expandOnHover) as? Bool ?? true
        musicLiveActivity = defaults.object(forKey: Keys.musicLive) as? Bool ?? true
        invertMouseCarousel = defaults.bool(forKey: "island.invertMouseCarousel")
        wakeWordEnabled = defaults.object(forKey: "voice.wakeEnabled") as? Bool ?? true
        wakeWord = defaults.string(forKey: "voice.wakeWord") ?? "Alt"
        wakeWordOnlyOnPower = defaults.bool(forKey: "voice.wakeOnlyOnPower")
        islandTheme = IslandTheme(rawValue: defaults.string(forKey: "island.theme") ?? "") ?? .normal
        voiceLocale = defaults.string(forKey: Keys.voiceLocale) ?? "pt-BR"
        voiceMicrophone = defaults.string(forKey: "voice.microphone") ?? "auto"
        voiceShortcut = AppSettings.loadShortcut(Keys.voiceShortcut,
            default: Shortcut(keyCode: 9, modifiers: Shortcut.controlOptionCommand, display: "⌃⌥⌘V"))
        islandShortcut = AppSettings.loadShortcut(Keys.islandShortcut,
            default: Shortcut(keyCode: 34, modifiers: Shortcut.controlOptionCommand, display: "⌃⌥⌘I"))
    }

    func registerHotKeys() {
        var bindings: [(Shortcut, () -> Void)] = []
        if let voiceShortcut, enabledFeatures.contains(.voice) {
            bindings.append((voiceShortcut, { IslandController.shared.startVoice() }))
        }
        if let islandShortcut {
            bindings.append((islandShortcut, { IslandController.shared.toggle() }))
        }
        HotKeyCenter.shared.setBindings(bindings, group: "app")
    }

    // MARK: - Persistência

    private func save(_ value: Any, _ key: String) {
        defaults.set(value, forKey: key)
    }

    private func saveShortcut(_ shortcut: Shortcut?, _ key: String) {
        // "none" distingue "sem atalho" de "nunca configurado".
        if let shortcut, let data = try? JSONEncoder().encode(shortcut) {
            defaults.set(data, forKey: key)
        } else {
            defaults.set("none", forKey: key)
        }
    }

    private static func loadShortcut(_ key: String, default value: Shortcut) -> Shortcut? {
        let stored = UserDefaults.standard.object(forKey: key)
        if stored as? String == "none" { return nil }
        if let data = stored as? Data, let shortcut = try? JSONDecoder().decode(Shortcut.self, from: data) {
            return shortcut
        }
        return value
    }
}

/// Aparência da ilha.
enum IslandTheme: String, CaseIterable, Identifiable {
    case normal, glass

    var id: String { rawValue }

    var title: String {
        switch self {
        case .normal: "Normal"
        case .glass: "Liquid Glass"
        }
    }
}

/// Funcionalidades da ilha que podem ser ligadas e desligadas.
enum Feature: String, CaseIterable, Identifiable {
    case music, notifications, voice, profiles, bluetooth, sound

    var id: String { rawValue }
    var defaultsKey: String { "feature.\(rawValue)" }
    var onByDefault: Bool { self == .music || self == .notifications }

    init(page: IslandPage) {
        switch page {
        case .music: self = .music
        case .notifications: self = .notifications
        case .voice: self = .voice
        case .profiles: self = .profiles
        case .bluetooth: self = .bluetooth
        case .sound: self = .sound
        }
    }

    var title: String {
        switch self {
        case .music: "Música"
        case .notifications: "Notificações"
        case .voice: "Voz"
        case .profiles: "Perfis de teclado"
        case .bluetooth: "Bluetooth"
        case .sound: "Som"
        }
    }

    var symbol: String {
        switch self {
        case .music: "music.note"
        case .notifications: "bell.fill"
        case .voice: "mic.fill"
        case .profiles: "switch.2"
        case .bluetooth: "antenna.radiowaves.left.and.right"
        case .sound: "speaker.wave.2.fill"
        }
    }

    var color: Color {
        switch self {
        case .music: .green
        case .notifications: .red
        case .voice: .purple
        case .profiles: .blue
        case .bluetooth: .blue
        case .sound: .pink
        }
    }

    /// "Música desligada", "Som desligado"…
    var offTitle: String {
        switch self {
        case .music: "Música desligada"
        case .notifications: "Notificações desligadas"
        case .voice: "Voz desligada"
        case .profiles: "Perfis de teclado desligados"
        case .bluetooth: "Bluetooth desligado"
        case .sound: "Som desligado"
        }
    }

    /// O que a funcionalidade faz (usado no aviso de desligada e nos Ajustes).
    var summary: String {
        switch self {
        case .music: "Controle o Spotify, veja playlists e busque músicas e podcasts."
        case .notifications: "Veja as notificações do Mac na ilha, com filtros por app e por tipo."
        case .voice: "Diga “Alt” e um comando para abrir apps, pastas, pesquisar e tocar música."
        case .profiles: "Troque idioma do teclado, rolagem e velocidade do mouse com um clique ou atalho."
        case .bluetooth: "Ligue o Bluetooth, conecte e pareie fones, teclados e mouses."
        case .sound: "Saída de áudio, volume geral e volume, mudo e saída de cada app."
        }
    }
}
