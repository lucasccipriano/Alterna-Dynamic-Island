import AppKit
import SwiftUI

/// Painel sem borda que pode receber teclado sem ativar o app (como o Spotlight).
final class IslandPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Aceita o primeiro clique mesmo com o app em segundo plano
/// (sem isso, o 1º clique só "acordava" a janela e não abria a ilha).
final class IslandHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Permite trocar o cursor mesmo com o app em segundo plano.
/// Usa uma propriedade interna do WindowServer (a mesma que apps de barra de menus usam).
enum BackgroundCursor {
    static func enable() {
        typealias DefaultConnection = @convention(c) () -> Int32
        typealias SetProperty = @convention(c) (Int32, Int32, CFString, CFTypeRef) -> Int32
        let handle = UnsafeMutableRawPointer(bitPattern: -2) // RTLD_DEFAULT
        guard let connSym = dlsym(handle, "_CGSDefaultConnection"),
              let setSym = dlsym(handle, "CGSSetConnectionProperty") else { return }
        let connection = unsafeBitCast(connSym, to: DefaultConnection.self)()
        _ = unsafeBitCast(setSym, to: SetProperty.self)(connection, connection,
                                                         "SetsCursorInBackground" as CFString, kCFBooleanTrue)
    }
}

/// Cria a janela da ilha sobre o notch e cuida de mouse, gestos e teclado.
@MainActor
final class IslandController {
    static let shared = IslandController()

    /// Área transparente fixa onde a ilha cresce. Só a parte preta recebe cliques.
    static let canvas = CGSize(width: 780, height: 420)

    let model = IslandModel.shared
    private var panel: IslandPanel?
    private var monitors: [Any] = []
    private var timer: Timer?
    private var expandWork: DispatchWorkItem?
    private var collapseWork: DispatchWorkItem?
    private var swipeAccumulator: CGFloat = 0
    private var swipeLocked = false
    private var showingHandCursor = false
    /// App que estava em uso antes de a ilha pegar o teclado (para devolver o foco ao fechar).
    private var previousApp: NSRunningApplication?
    private var wheelAccumulator: CGFloat = 0
    private var wheelLastEvent = Date.distantPast
    private var wheelCooldownUntil = Date.distantPast

    private init() {}

    // MARK: - Ciclo de vida

    func start() {
        guard panel == nil else { return }

        let panel = IslandPanel(contentRect: NSRect(origin: .zero, size: Self.canvas),
                                styleMask: [.borderless, .nonactivatingPanel],
                                backing: .buffered,
                                defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.mainMenuWindow)) + 3)
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.isMovable = false
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.acceptsMouseMovedEvents = true
        panel.ignoresMouseEvents = true
        panel.animationBehavior = .none

        BackgroundCursor.enable()
        let host = IslandHostingView(rootView: IslandRootView())
        host.frame = NSRect(origin: .zero, size: Self.canvas)
        panel.contentView = host
        self.panel = panel

        reposition()
        installMonitors()

        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.reposition() }
        }

        setVisible(AppSettings.shared.showIsland)
    }

    func setVisible(_ visible: Bool) {
        guard let panel else { return }
        if visible {
            panel.orderFrontRegardless()
        } else {
            collapse()
            panel.orderOut(nil)
        }
    }

    /// Prefere a tela com notch (a do MacBook); senão, a principal.
    private func targetScreen() -> NSScreen? {
        NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main ?? NSScreen.screens.first
    }

    private func reposition() {
        guard let panel, let screen = targetScreen() else { return }
        model.geometry = NotchGeometry(screen: screen)
        let origin = NSPoint(x: screen.frame.midX - Self.canvas.width / 2,
                             y: screen.frame.maxY - Self.canvas.height)
        panel.setFrame(NSRect(origin: origin, size: Self.canvas), display: true)
    }

    // MARK: - Abrir e fechar

    func expand(to page: IslandPage? = nil) {
        guard AppSettings.shared.showIsland else { return }
        if let page { model.go(to: page) }
        model.dismissActivity()
        expandWork?.cancel(); expandWork = nil
        let wasExpanded = model.isExpanded
        // 1º tempo: alarga com mola elástica.
        withAnimation(.islandOpen) {
            model.isExpanded = true
            model.isPreviewing = false
        }
        panel?.ignoresMouseEvents = false
        // Recebe teclado e hover já na abertura, sem precisar de um clique antes.
        let front = NSWorkspace.shared.frontmostApplication
        if front?.processIdentifier != ProcessInfo.processInfo.processIdentifier { previousApp = front }
        if let panel, !panel.isKeyWindow { panel.makeKey() }
        // 2º tempo: estica para baixo, como na animação do Sportio.
        if !wasExpanded {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.07) { [weak self] in
                guard let self, self.model.isExpanded else { return }
                withAnimation(.islandStretch) { self.model.expandedHeightReady = true }
            }
        }
    }

    /// Prévia ao passar o mouse.
    func showPreview() {
        guard !model.isExpanded, model.activity == nil, !model.isPreviewing else { return }
        model.resetPreviewPage()
        withAnimation(.islandOpen) { model.isPreviewing = true }
        panel?.ignoresMouseEvents = false
        setHandCursor(true)
    }

    func hidePreview() {
        guard model.isPreviewing else { return }
        withAnimation(.islandClose) { model.isPreviewing = false }
    }

    // MARK: - Ativação por voz ("Alt")

    /// Ouviu a palavra de ativação: abre a prévia de voz mostrando que está ouvindo.
    func showListeningPreview() {
        guard AppSettings.shared.showIsland else { return }
        model.keepOpen = true
        if model.isExpanded {
            model.go(to: .voice)
            return
        }
        model.dismissActivity()
        model.setPreviewPage(.voice)
        withAnimation(.islandOpen) { model.isPreviewing = true }
    }

    /// Terminou: mostra o resultado e fecha (ou abre a ilha, se precisar escolher algo).
    func endListeningPreview(result: CommandResult?) {
        model.keepOpen = false
        let mouseInside = islandRect().contains(NSEvent.mouseLocation)

        if let result, result.needsExpandedView {
            expand(to: .voice)
            return
        }
        if model.isExpanded { return }
        if !mouseInside { hidePreview() }
        if let result {
            let info = result.banner
            model.present(IslandActivity(icon: .symbol(info.symbol, .accentColor),
                                         title: info.title, subtitle: info.subtitle,
                                         duration: 2.6, page: .voice))
        }
    }

    func collapse() {
        expandWork?.cancel(); expandWork = nil
        collapseWork?.cancel(); collapseWork = nil
        hidePreview()
        guard model.isExpanded else { return }
        model.keepOpen = false
        panel?.makeFirstResponder(nil)
        // Devolve o teclado para o app que você estava usando.
        if panel?.isKeyWindow == true {
            panel?.resignKey()
            previousApp?.activate()
        }
        previousApp = nil
        withAnimation(.islandClose) {
            model.isExpanded = false
            model.expandedHeightReady = false
        }
    }

    func toggle() {
        model.isExpanded ? collapse() : expand()
    }

    /// Pede o teclado para a ilha (campos de texto).
    func focus() {
        panel?.makeKey()
    }

    func startVoice() {
        expand(to: .voice)
        guard AppSettings.shared.isEnabled(.voice) else { return }
        model.keepOpen = true
        VoiceController.shared.startListening()
    }

    func runCommand(_ text: String) {
        expand(to: .voice)
        guard AppSettings.shared.isEnabled(.voice) else { return }
        model.keepOpen = true
        VoiceController.shared.run(text)
    }

    // MARK: - Mouse

    /// Retângulo da parte preta, em coordenadas de tela.
    private func islandRect() -> NSRect {
        guard let panel else { return .zero }
        let size = model.bodySize
        let frame = panel.frame
        var rect = NSRect(x: frame.midX - size.width / 2,
                          y: frame.maxY - size.height,
                          width: size.width,
                          height: size.height)
        rect = rect.insetBy(dx: model.isExpanded ? -6 : -14, dy: model.isExpanded ? -6 : -6)
        return rect
    }

    private func handleMouseMoved() {
        guard let panel, panel.isVisible else { return }
        let inside = islandRect().contains(NSEvent.mouseLocation)
        panel.ignoresMouseEvents = !inside
        // Fechada ou em prévia, a ilha inteira é clicável: mãozinha assim que o mouse entra.
        setHandCursor(inside && !model.isExpanded)

        if inside {
            collapseWork?.cancel(); collapseWork = nil
            // Passar o mouse mostra a prévia; o clique abre por completo.
            guard !model.isExpanded, !model.isPreviewing, model.activity == nil,
                  AppSettings.shared.expandOnHover, expandWork == nil else { return }
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.expandWork = nil
                guard self.islandRect().contains(NSEvent.mouseLocation) else { return }
                self.showPreview()
            }
            expandWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: work)
        } else {
            expandWork?.cancel(); expandWork = nil
            let shouldClose = (model.isPreviewing || model.isExpanded) && !model.keepOpen
            guard shouldClose, collapseWork == nil else { return }
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.collapseWork = nil
                guard !self.islandRect().contains(NSEvent.mouseLocation), !self.model.keepOpen else { return }
                if self.model.isExpanded { self.collapse() } else { self.hidePreview() }
            }
            collapseWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + (model.isPreviewing ? 0.25 : 0.45), execute: work)
        }
    }

    private func installMonitors() {
        let moved: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged]

        if let global = NSEvent.addGlobalMonitorForEvents(matching: moved, handler: { [weak self] _ in
            Task { @MainActor in self?.handleMouseMoved() }
        }) { monitors.append(global) }

        // Clique fora fecha a ilha, mesmo se ela estiver presa aberta.
        if let outside = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { [weak self] _ in
            Task { @MainActor in
                guard let self, self.model.isExpanded,
                      !self.islandRect().contains(NSEvent.mouseLocation) else { return }
                self.collapse()
            }
        }) { monitors.append(outside) }

        if let local = NSEvent.addLocalMonitorForEvents(matching: moved, handler: { [weak self] event in
            self?.handleMouseMoved()
            return event
        }) { monitors.append(local) }

        if let scroll = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel, handler: { [weak self] event in
            self?.handleScroll(event) ?? event
        }) { monitors.append(scroll) }

        if let keys = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
            self?.handleKey(event) ?? event
        }) { monitors.append(keys) }

        // Segurança: confere a posição do mouse de tempos em tempos.
        timer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.handleMouseMoved() }
        }
    }

    // MARK: - Gesto de dois dedos (carrossel)

    private func handleScroll(_ event: NSEvent) -> NSEvent? {
        guard event.window === panel, model.isExpanded || model.isPreviewing else { return event }

        // Mouse (roda lateral, botão de inclinar ou Shift + roda): eventos sem fase.
        if event.phase.isEmpty && event.momentumPhase.isEmpty {
            return handleMouseWheel(event)
        }
        guard event.hasPreciseScrollingDeltas else { return event }

        if event.phase == .began || event.phase == .mayBegin {
            swipeAccumulator = 0
            swipeLocked = false
        }
        if event.phase == .ended || event.phase == .cancelled {
            swipeAccumulator = 0
            swipeLocked = false
            return event
        }
        // Ignora a inércia depois que os dedos saem do trackpad.
        guard event.momentumPhase.isEmpty else { return event }

        let dx = event.scrollingDeltaX
        let dy = event.scrollingDeltaY
        guard abs(dx) > abs(dy) * 1.4 else { return event }

        // Direção física dos dedos, independente da rolagem natural.
        let finger = event.isDirectionInvertedFromDevice ? dx : -dx
        swipeAccumulator += finger

        if !swipeLocked {
            if swipeAccumulator < -55 {
                model.step(1); swipeLocked = true
            } else if swipeAccumulator > 55 {
                model.step(-1); swipeLocked = true
            }
        }
        return nil
    }

    /// Roda horizontal do mouse: cada "clique" da roda (ou um giro contínuo) troca uma página.
    private func handleMouseWheel(_ event: NSEvent) -> NSEvent? {
        let dx = event.scrollingDeltaX
        let dy = event.scrollingDeltaY
        guard dx != 0, abs(dx) > abs(dy) else { return event }

        let now = Date()
        if now.timeIntervalSince(wheelLastEvent) > 0.3 { wheelAccumulator = 0 }
        wheelLastEvent = now
        guard now >= wheelCooldownUntil else { return nil }

        // Direção física da roda (sem a inversão da rolagem natural).
        var physical = event.isDirectionInvertedFromDevice ? -dx : dx
        if AppSettings.shared.invertMouseCarousel { physical = -physical }
        wheelAccumulator += event.hasPreciseScrollingDeltas ? physical / 12 : physical

        if abs(wheelAccumulator) >= 1 {
            // Roda para a direita = próxima página.
            model.step(wheelAccumulator < 0 ? 1 : -1)
            wheelAccumulator = 0
            wheelCooldownUntil = now.addingTimeInterval(0.35)
        }
        return nil
    }

    private func setHandCursor(_ hand: Bool) {
        if hand {
            NSCursor.pointingHand.set()
            showingHandCursor = true
        } else if showingHandCursor {
            NSCursor.arrow.set()
            showingHandCursor = false
        }
    }

    // MARK: - Teclado

    private func handleKey(_ event: NSEvent) -> NSEvent? {
        guard event.window === panel, model.isExpanded else { return event }
        let editing = panel?.firstResponder is NSTextView

        switch event.keyCode {
        case 53: // Esc
            if editing {
                panel?.makeFirstResponder(nil)
            } else {
                collapse()
            }
            return nil
        case 123 where !editing: // ←
            model.previous(); return nil
        case 124 where !editing: // →
            model.next(); return nil
        default:
            return event
        }
    }
}
