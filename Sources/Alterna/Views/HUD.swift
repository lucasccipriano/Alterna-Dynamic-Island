import AppKit
import SwiftUI

/// Aviso flutuante no estilo do HUD de volume/brilho do macOS.
@MainActor
final class HUD {
    static let shared = HUD()

    private var panel: NSPanel?
    private var hideTask: Task<Void, Never>?

    func show(symbol: String, title: String, subtitle: String) {
        // Com a Dynamic Island ligada, o aviso aparece nela.
        if AppSettings.shared.showIsland {
            IslandModel.shared.present(IslandActivity(icon: .symbol(symbol, .accentColor),
                                                      title: title, subtitle: subtitle,
                                                      duration: 2.2, page: .profiles))
            return
        }
        let panel = self.panel ?? makePanel()
        self.panel = panel

        let host = NSHostingView(rootView: HUDView(symbol: symbol, title: title, subtitle: subtitle))
        let size = host.fittingSize
        host.frame = NSRect(origin: .zero, size: size)
        panel.contentView = host
        panel.setContentSize(size)

        if let screen = NSScreen.main {
            let frame = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: frame.midX - size.width / 2,
                                         y: frame.minY + frame.height * 0.16))
        }

        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            panel.animator().alphaValue = 1
        }

        hideTask?.cancel()
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.3))
            guard !Task.isCancelled else { return }
            self?.hide()
        }
    }

    private func hide() {
        guard let panel else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.35
            panel.animator().alphaValue = 0
        }
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: .zero,
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered,
                            defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar
        panel.ignoresMouseEvents = true
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        return panel
    }
}

private struct HUDView: View {
    let symbol: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 52, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .frame(height: 64)
            VStack(spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .padding(20)
        .frame(width: 200, height: 200)
        .background(.ultraThickMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08))
        )
        .padding(12) // espaço para a sombra
        .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
    }
}
