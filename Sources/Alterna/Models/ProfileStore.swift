import AppKit
import Combine
import ServiceManagement

/// Estado central: perfis, atalhos e aplicação dos ajustes no sistema.
@MainActor
final class ProfileStore: ObservableObject {
    static let shared = ProfileStore()

    @Published var profiles: [Profile] {
        didSet {
            persist()
            if profiles.map(\.shortcut) != oldValue.map(\.shortcut) { registerHotKeys() }
        }
    }

    @Published var activeProfileID: UUID? {
        didSet { defaults.set(activeProfileID?.uuidString, forKey: Keys.active) }
    }

    /// Atalho que passa para o próximo perfil da lista.
    @Published var cycleShortcut: Shortcut? {
        didSet { persist(); registerHotKeys() }
    }

    /// Liga ou desliga toda a função de perfis (página Alternar e atalhos dos perfis).
    @Published var profilesEnabled: Bool {
        didSet {
            guard profilesEnabled != oldValue else { return }
            defaults.set(profilesEnabled, forKey: Keys.enabled)
            registerHotKeys()
        }
    }

    @Published var showHUD: Bool {
        didSet { defaults.set(showHUD, forKey: Keys.hud) }
    }

    @Published private(set) var reverseMouseWheel: Bool
    @Published private(set) var accessibilityGranted = ScrollInverter.isTrusted
    @Published private(set) var inputSources: [InputSource] = []
    @Published private(set) var currentInputSource: InputSource?

    private let defaults = UserDefaults.standard
    private var observers: [NSObjectProtocol] = []
    private var permissionTimer: Timer?

    private enum Keys {
        static let profiles = "profiles"
        static let active = "activeProfile"
        static let cycle = "cycleShortcut"
        static let hud = "showHUD"
        static let enabled = "feature.profiles"
        static let reverse = "reverseMouseWheel"
    }

    private init() {
        // Variável local: `self` ainda não pode ser usado antes de iniciar tudo.
        let defaults = UserDefaults.standard
        let decoder = JSONDecoder()

        if let data = defaults.data(forKey: Keys.profiles),
           let saved = try? decoder.decode([Profile].self, from: data) {
            profiles = saved
        } else {
            profiles = ProfileStore.defaultProfiles()
        }

        if let data = defaults.data(forKey: Keys.cycle) {
            cycleShortcut = try? decoder.decode(Shortcut.self, from: data)
        } else {
            cycleShortcut = Shortcut(keyCode: 49, modifiers: Shortcut.controlOptionCommand, display: "⌃⌥⌘Espaço")
        }

        activeProfileID = defaults.string(forKey: Keys.active).flatMap { UUID(uuidString: $0) }
        showHUD = defaults.object(forKey: Keys.hud) as? Bool ?? true
        profilesEnabled = defaults.object(forKey: Keys.enabled) as? Bool ?? false
        reverseMouseWheel = defaults.bool(forKey: Keys.reverse)

        refreshStatus()
        persist()
        registerHotKeys()
        observeSystem()
        // Ao abrir o app não mostra o pedido de permissão: só liga quando já foi dada.
        if reverseMouseWheel { startInverterWhenPossible(prompt: false) }
    }

    var activeProfile: Profile? {
        profiles.first { $0.id == activeProfileID }
    }

    // MARK: - Aplicar

    func apply(_ profile: Profile) {
        var subtitle: String?

        if let id = profile.inputSourceID {
            subtitle = InputSources.select(id: id)
                ? (InputSources.name(for: id) ?? id)
                : "Fonte de entrada não encontrada"
        }
        if let natural = profile.naturalScrolling {
            ScrollDirection.setNatural(natural)
        }
        if let reverse = profile.reverseMouseWheel {
            setReverseMouseWheel(reverse)
        }
        if let speed = profile.mouseSpeed {
            PointerSpeed.set(.mouse, to: speed)
        }
        if let speed = profile.trackpadSpeed {
            PointerSpeed.set(.trackpad, to: speed)
        }

        activeProfileID = profile.id
        refreshStatus()

        if showHUD {
            HUD.shared.show(symbol: profile.symbol,
                            title: profile.name,
                            subtitle: subtitle ?? "Perfil aplicado")
        }
    }

    func applyNext() {
        guard !profiles.isEmpty else { return }
        let next = profiles.firstIndex { $0.id == activeProfileID }
            .map { ($0 + 1) % profiles.count } ?? 0
        apply(profiles[next])
    }

    // MARK: - Edição

    @discardableResult
    func addProfile() -> Profile {
        let profile = snapshot(Profile(name: "Novo perfil", symbol: "person.fill"))
        profiles.append(profile)
        return profile
    }

    func deleteProfile(id: UUID) {
        if activeProfileID == id { activeProfileID = nil }
        profiles.removeAll { $0.id == id }
    }

    /// Copia os ajustes atuais do Mac para o perfil.
    func snapshot(_ profile: Profile) -> Profile {
        var p = profile
        p.inputSourceID = InputSources.current()?.id
        p.naturalScrolling = ScrollDirection.isNatural
        p.reverseMouseWheel = reverseMouseWheel
        p.mouseSpeed = PointerSpeed.current(.mouse)
        p.trackpadSpeed = PointerSpeed.current(.trackpad)
        return p
    }

    // MARK: - Rolagem só do mouse

    func setReverseMouseWheel(_ on: Bool) {
        reverseMouseWheel = on
        defaults.set(on, forKey: Keys.reverse)
        if on {
            startInverterWhenPossible()
        } else {
            ScrollInverter.shared.stop()
            permissionTimer?.invalidate()
            permissionTimer = nil
        }
    }

    func requestAccessibility() {
        ScrollInverter.requestPermission()
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
        watchPermission()
    }

    private func startInverterWhenPossible(prompt: Bool = true) {
        if ScrollInverter.shared.start() {
            accessibilityGranted = true
            return
        }
        if prompt { ScrollInverter.requestPermission() }
        watchPermission()
    }

    /// Depois que a pessoa autoriza em Ajustes do Sistema, liga o inversor sozinho.
    private func watchPermission() {
        permissionTimer?.invalidate()
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.accessibilityGranted = ScrollInverter.isTrusted
                guard self.accessibilityGranted else { return }
                if self.reverseMouseWheel { ScrollInverter.shared.start() }
                self.permissionTimer?.invalidate()
                self.permissionTimer = nil
            }
        }
    }

    // MARK: - Abrir ao iniciar sessão

    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            objectWillChange.send()
            do {
                if newValue { try SMAppService.mainApp.register() }
                else { try SMAppService.mainApp.unregister() }
            } catch {
                NSLog("Alterna: não foi possível alterar o item de início: \(error)")
            }
        }
    }

    // MARK: - Estado do sistema

    func refreshStatus() {
        inputSources = InputSources.all()
        currentInputSource = InputSources.current()
        accessibilityGranted = ScrollInverter.isTrusted
    }

    private func observeSystem() {
        let center = DistributedNotificationCenter.default()
        let names = [
            "com.apple.Carbon.TISNotifySelectedKeyboardInputSourceChanged",
            "com.apple.Carbon.TISNotifyEnabledKeyboardInputSourcesChanged"
        ]
        for name in names {
            let token = center.addObserver(forName: Notification.Name(name), object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.refreshStatus() }
            }
            observers.append(token)
        }
    }

    // MARK: - Atalhos globais

    private func registerHotKeys() {
        var bindings: [(Shortcut, () -> Void)] = []
        // Desligado: nenhum atalho de perfil fica registrado.
        guard profilesEnabled else { HotKeyCenter.shared.setBindings(bindings); return }
        for profile in profiles {
            guard let shortcut = profile.shortcut else { continue }
            let id = profile.id
            bindings.append((shortcut, { [weak self] in
                guard let self, let p = self.profiles.first(where: { $0.id == id }) else { return }
                self.apply(p)
            }))
        }
        if let cycle = cycleShortcut {
            bindings.append((cycle, { [weak self] in self?.applyNext() }))
        }
        HotKeyCenter.shared.setBindings(bindings)
    }

    // MARK: - Persistência

    private func persist() {
        let encoder = JSONEncoder()
        defaults.set(try? encoder.encode(profiles), forKey: Keys.profiles)
        defaults.set(try? encoder.encode(cycleShortcut), forKey: Keys.cycle)
    }

    private static func defaultProfiles() -> [Profile] {
        let source = InputSources.current()?.id
        let natural = ScrollDirection.isNatural
        let mods = Shortcut.controlOptionCommand
        return [
            Profile(name: "Trabalho", symbol: "briefcase.fill",
                    shortcut: Shortcut(keyCode: 18, modifiers: mods, display: "⌃⌥⌘1"),
                    inputSourceID: source, naturalScrolling: natural),
            Profile(name: "Lazer", symbol: "gamecontroller.fill",
                    shortcut: Shortcut(keyCode: 19, modifiers: mods, display: "⌃⌥⌘2"),
                    inputSourceID: source, naturalScrolling: !natural)
        ]
    }
}
