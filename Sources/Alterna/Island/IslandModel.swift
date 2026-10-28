import AppKit
import SwiftUI

// MARK: - Páginas do carrossel

enum IslandPage: Int, CaseIterable, Identifiable {
    case music, notifications, voice, profiles, bluetooth, sound

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .music: "Música"
        case .notifications: "Notificações"
        case .voice: "Comando"
        case .profiles: "Alternar"
        case .bluetooth: "Bluetooth"
        case .sound: "Som"
        }
    }

    var symbol: String {
        switch self {
        case .music: "music.note"
        case .notifications: "bell.fill"
        case .voice: "waveform"
        case .profiles: "switch.2"
        case .bluetooth: "antenna.radiowaves.left.and.right"
        case .sound: "speaker.wave.2.fill"
        }
    }

    /// Nome usado nos links alterna://pagina/<slug>
    var slug: String {
        switch self {
        case .music: "musica"
        case .notifications: "notificacoes"
        case .voice: "comando"
        case .profiles: "alternar"
        case .bluetooth: "bluetooth"
        case .sound: "som"
        }
    }
}

// MARK: - Atividade passageira (banner)

enum ActivityIcon {
    case symbol(String, Color)
    case app(String)        // bundle id
    case image(NSImage)
}

struct IslandActivity: Identifiable, Equatable {
    let id = UUID()
    var icon: ActivityIcon
    var title: String
    var subtitle: String
    var duration: TimeInterval = 3
    var page: IslandPage? = nil       // página aberta ao passar o mouse
    var action: (() -> Void)? = nil   // clique no banner

    static func == (lhs: IslandActivity, rhs: IslandActivity) -> Bool { lhs.id == rhs.id }
}

// MARK: - Geometria do notch

struct NotchGeometry: Equatable {
    var width: CGFloat
    var height: CGFloat
    var hasNotch: Bool

    static let fallback = NotchGeometry(width: 180, height: 32, hasNotch: false)

    init(width: CGFloat, height: CGFloat, hasNotch: Bool) {
        self.width = width
        self.height = height
        self.hasNotch = hasNotch
    }

    init(screen: NSScreen) {
        if screen.safeAreaInsets.top > 0,
           let left = screen.auxiliaryTopLeftArea,
           let right = screen.auxiliaryTopRightArea {
            width = screen.frame.width - left.width - right.width
            height = screen.safeAreaInsets.top
            hasNotch = true
        } else {
            // Tela sem notch: uma pílula do tamanho da barra de menus.
            width = 180
            height = max(NSStatusBar.system.thickness, 24)
            hasNotch = false
        }
    }
}

extension Animation {
    /// Mola parecida com a da Dynamic Island do iPhone.
    static let island = Animation.spring(response: 0.42, dampingFraction: 0.82)
    /// Abrir: mola elástica que passa um pouco do ponto e volta (efeito "gota").
    static let islandOpen = Animation.spring(response: 0.42, dampingFraction: 0.7, blendDuration: 0.1)
    /// Segundo tempo da abertura: a ilha estica para baixo depois de alargar.
    static let islandStretch = Animation.spring(response: 0.48, dampingFraction: 0.72)
    /// Fechar: rápida e sem quicar.
    static let islandClose = Animation.spring(response: 0.36, dampingFraction: 0.92)
}

// MARK: - Estado da ilha

@MainActor
final class IslandModel: ObservableObject {
    static let shared = IslandModel()

    @Published var isExpanded = false
    @Published private(set) var page: IslandPage
    @Published private(set) var direction: Edge = .trailing
    @Published private(set) var activity: IslandActivity?
    @Published var geometry = NotchGeometry.fallback
    /// Mantém a ilha aberta (digitando, ouvindo, pareando…).
    @Published var keepOpen = false
    /// Prévia: aparece ao passar o mouse; um clique abre por completo.
    @Published var isPreviewing = false
    /// Seção mostrada na prévia (dá para rolar entre elas).
    @Published private(set) var previewPage: IslandPage = .music
    @Published private(set) var previewDirection: Edge = .trailing
    /// Abertura em dois tempos: primeiro alarga, depois desce (efeito de esticar).
    @Published var expandedHeightReady = false

    private var activityTask: Task<Void, Never>?

    static let expandedWidth: CGFloat = 620
    static let expandedContentHeight: CGFloat = 276

    private init() {
        let saved = UserDefaults.standard.integer(forKey: "island.page")
        page = IslandPage(rawValue: saved) ?? .music
    }

    // MARK: Navegação

    func go(to newPage: IslandPage) {
        guard newPage != page else { return }
        direction = newPage.rawValue > page.rawValue ? .trailing : .leading
        withAnimation(.island) { page = newPage }
        UserDefaults.standard.set(newPage.rawValue, forKey: "island.page")
    }

    func next() {
        if let p = IslandPage(rawValue: page.rawValue + 1) { go(to: p) }
    }

    func previous() {
        if let p = IslandPage(rawValue: page.rawValue - 1) { go(to: p) }
    }

    func goPreview(to newPage: IslandPage) {
        guard newPage != previewPage else { return }
        previewDirection = newPage.rawValue > previewPage.rawValue ? .trailing : .leading
        withAnimation(.island) { previewPage = newPage }
    }

    /// Prévia começa na música se estiver tocando; senão, na última seção usada.
    func setPreviewPage(_ newPage: IslandPage) {
        previewPage = newPage
    }

    func resetPreviewPage() {
        previewPage = SpotifyController.shared.isPlaying ? .music : page
    }

    /// Gesto de carrossel: vale para a ilha aberta e para a prévia.
    func step(_ delta: Int) {
        if isExpanded {
            if delta > 0 { next() } else { previous() }
        } else if isPreviewing, let p = IslandPage(rawValue: previewPage.rawValue + delta) {
            goPreview(to: p)
        }
    }

    // MARK: Atividades

    func present(_ newActivity: IslandActivity) {
        guard AppSettings.shared.showIsland else { return }
        activityTask?.cancel()
        withAnimation(.island) { activity = newActivity }
        let id = newActivity.id
        activityTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(newActivity.duration))
            guard !Task.isCancelled, let self, self.activity?.id == id else { return }
            withAnimation(.island) { self.activity = nil }
        }
    }

    func dismissActivity() {
        activityTask?.cancel()
        withAnimation(.island) { activity = nil }
    }

    // MARK: Tamanho

    var showsMusicActivity: Bool {
        AppSettings.shared.musicLiveActivity && SpotifyController.shared.isPlaying
    }

    var showsVoiceActivity: Bool {
        VoiceController.shared.isListening
    }

    /// Tamanho do corpo preto da ilha (sem as "abas" do topo).
    var bodySize: CGSize {
        let g = geometry
        if isExpanded {
            let height = expandedHeightReady ? g.height + Self.expandedContentHeight : g.height + 72
            return CGSize(width: max(Self.expandedWidth, g.width + 340), height: height)
        }
        if activity != nil {
            return CGSize(width: max(g.width + 220, 400), height: g.height + 62)
        }
        if isPreviewing {
            return CGSize(width: max(g.width + 300, 480), height: g.height + 78)
        }
        if showsVoiceActivity || showsMusicActivity {
            return CGSize(width: g.width + 2 * (g.height + 10), height: g.height)
        }
        return CGSize(width: g.width, height: g.height)
    }

    var topRadius: CGFloat {
        if isExpanded { return 14 }
        return (activity != nil || isPreviewing) ? 10 : 6
    }

    var bottomRadius: CGFloat {
        if isExpanded { return 34 }
        if activity != nil || isPreviewing { return 26 }
        return geometry.height * 0.34
    }
}
