import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Registrado aqui (depois do SwiftUI) para receber os links alterna://
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleURLEvent(_:withReply:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL))

        _ = ProfileStore.shared
        AppSettings.shared.registerHotKeys()
        IslandController.shared.start()
        // Só liga o que estiver ativado em Ajustes › Geral › Funcionalidades.
        for feature in Feature.allCases { AppSettings.shared.apply(feature) }
    }

    /// Abrir o app de novo (Aplicativos, Spotlight, Launchpad) mostra os Ajustes.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        SettingsWindowController.shared.show()
        return false
    }

    @objc private func handleURLEvent(_ event: NSAppleEventDescriptor, withReply reply: NSAppleEventDescriptor) {
        guard let text = event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))?.stringValue,
              let url = URL(string: text) else { return }
        URLRouter.handle(url)
    }
}

/// Links aceitos (usados pelo Atalho da Siri):
///   alterna://ouvir                      abre a ilha já ouvindo
///   alterna://comando?texto=abrir%20notas executa um comando de texto
///   alterna://pagina/musica              abre a ilha numa página
enum URLRouter {
    @MainActor
    static func handle(_ url: URL) {
        guard url.scheme?.lowercased() == "alterna" else { return }
        let host = (url.host ?? "").lowercased()
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []

        switch host {
        case "ouvir", "voz", "siri":
            IslandController.shared.startVoice()
        case "comando", "command":
            let text = query.first { ["texto", "text", "q"].contains($0.name) }?.value ?? ""
            IslandController.shared.runCommand(text)
        case "pagina", "page":
            let name = url.pathComponents.dropFirst().first?.lowercased() ?? ""
            let page = IslandPage.allCases.first { $0.slug == name } ?? .music
            IslandController.shared.expand(to: page)
        default:
            IslandController.shared.expand(to: IslandModel.shared.page)
        }
    }
}
