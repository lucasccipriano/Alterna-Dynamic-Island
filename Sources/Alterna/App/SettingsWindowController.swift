import AppKit
import SwiftUI

/// Janela de Ajustes própria (o app não tem Dock nem menu principal).
@MainActor
final class SettingsWindowController: ObservableObject {
    static let shared = SettingsWindowController()

    /// Página pedida de fora (ex.: "music"); a janela de Ajustes vai até ela.
    @Published var requestedPane: String?

    private var window: NSWindow?

    func show(pane: String? = nil) {
        if let pane { requestedPane = pane }
        if window == nil {
            let root = SettingsView()
                .environmentObject(ProfileStore.shared)
                .environmentObject(AppSettings.shared)
            let controller = NSHostingController(rootView: root)
            let window = NSWindow(contentViewController: controller)
            window.title = "Ajustes do Alterna"
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
            window.toolbarStyle = .unified
            window.isReleasedWhenClosed = false
            window.setContentSize(NSSize(width: 820, height: 600))
            window.center()
            window.setFrameAutosaveName("AlternaSettings")
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
