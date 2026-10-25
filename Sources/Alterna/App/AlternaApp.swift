import SwiftUI

/// App sem Dock e sem ícone na barra de menus: tudo acontece na Dynamic Island.
/// Os Ajustes abrem pela engrenagem da ilha ou abrindo o app de novo em Aplicativos.
@main
struct AlternaApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // O SwiftUI exige ao menos uma cena; a janela de Ajustes real é a do SettingsWindowController.
        Settings {
            EmptyView()
        }
    }
}
