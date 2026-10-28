import AppKit
import Combine

/// Preferências gerais do app (a ilha, atalhos do app e voz).
@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

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
        if let voiceShortcut {
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
