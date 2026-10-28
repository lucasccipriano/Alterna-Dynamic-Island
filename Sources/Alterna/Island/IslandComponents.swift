import AppKit
import SwiftUI

// Peças visuais reaproveitadas pelas páginas da ilha.
// Tudo sobre fundo preto, como a Dynamic Island: texto branco,
// cinzas por opacidade, cantos contínuos e símbolos SF.

enum IslandStyle {
    static let card = Color.white.opacity(0.08)
    static let cardHover = Color.white.opacity(0.14)
    static let secondary = Color.white.opacity(0.6)
    static let tertiary = Color.white.opacity(0.38)
}

/// Abre a janela de Ajustes de um app de barra de menus.
enum SettingsOpener {
    @MainActor
    static func open() {
        IslandController.shared.collapse()
        SettingsWindowController.shared.show()
    }

    static func openSystemSettings(_ anchor: String) {
        if let url = URL(string: "x-apple.systempreferences:\(anchor)") {
            NSWorkspace.shared.open(url)
        }
    }
}

/// Botão redondo só com ícone (controles do player etc.).
struct RoundIconButton: View {
    let symbol: String
    var size: CGFloat = 28
    var weight: Font.Weight = .semibold
    var isOn = false
    var help: String = ""
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size * 0.5, weight: weight))
                .foregroundStyle(isOn ? Color.accentColor : .white)
                .frame(width: size, height: size)
                .background(Circle().fill(.white.opacity(hovering ? 0.14 : 0)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .linkCursor()
        .help(help)
        .accessibilityLabel(help)
    }
}

/// Botão em cápsula (ações secundárias).
struct CapsuleButton: View {
    let title: String
    var symbol: String? = nil
    var prominent = false
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let symbol { Image(systemName: symbol) }
                Text(title)
            }
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(prominent ? Color.black : .white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule().fill(prominent ? Color.white.opacity(hovering ? 0.85 : 1)
                                         : Color.white.opacity(hovering ? 0.2 : 0.12))
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .linkCursor()
    }
}

/// Linha clicável com destaque ao passar o mouse.
struct HoverRow<Content: View>: View {
    var action: (() -> Void)?
    @ViewBuilder var content: () -> Content
    @State private var hovering = false

    var body: some View {
        content()
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(hovering && action != nil ? IslandStyle.cardHover : Color.clear)
            )
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .onHover { hovering = $0 }
            .linkCursor(action != nil)
            .onTapGesture { action?() }
    }
}

/// Seletor em cápsulas, parecido com um segmented control escuro.
struct IslandSegmented<T: Hashable>: View {
    @Binding var selection: T
    let options: [(value: T, title: String)]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options.indices, id: \.self) { index in
                let option = options[index]
                let active = option.value == selection
                Text(option.title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(active ? Color.black : IslandStyle.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(active ? Color.white : Color.clear))
                    .contentShape(Capsule())
                    .linkCursor(!active)
                    .onTapGesture {
                        withAnimation(.island) { selection = option.value }
                    }
            }
        }
        .padding(2)
        .background(Capsule().fill(IslandStyle.card))
    }
}

/// Campo de busca arredondado que pede o teclado para a ilha.
struct IslandSearchField: View {
    let prompt: String
    @Binding var text: String
    var symbol = "magnifyingglass"
    var onSubmit: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .foregroundStyle(IslandStyle.tertiary)
            TextField("", text: $text, prompt: Text(prompt).foregroundColor(IslandStyle.tertiary))
                .textFieldStyle(.plain)
                .foregroundStyle(.white)
                .focused($focused)
                .onSubmit(onSubmit)
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(IslandStyle.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .font(.system(size: 13))
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(IslandStyle.card))
        .onTapGesture {
            IslandController.shared.focus()
            focused = true
        }
        .onChange(of: focused) { _, isFocused in
            IslandModel.shared.keepOpen = isFocused || VoiceController.shared.isListening
        }
    }
}

/// Ícone de um app pelo bundle id.
struct AppIconView: View {
    let bundleID: String
    var size: CGFloat = 28

    var body: some View {
        Image(nsImage: AppInfo.icon(for: bundleID))
            .resizable()
            .interpolation(.high)
            .frame(width: size, height: size)
    }
}

/// Capa de álbum com um fundo de espera.
struct ArtworkView: View {
    let image: NSImage?
    var size: CGFloat
    var radius: CGFloat = 10

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(IslandStyle.card)
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Image(systemName: "music.note")
                    .font(.system(size: size * 0.4, weight: .semibold))
                    .foregroundStyle(IslandStyle.tertiary)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

/// Estado vazio ou de permissão, centralizado.
struct IslandEmptyState: View {
    let symbol: String
    let title: String
    let message: String
    var buttonTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(IslandStyle.secondary)
                .symbolRenderingMode(.hierarchical)
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(IslandStyle.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
            if let buttonTitle, let action {
                CapsuleButton(title: buttonTitle, prominent: true, action: action)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Botão de voz: círculo com as cores da Siri e um microfone branco bem legível.
/// Ouvindo, o ícone vira uma onda animada e um anel pulsa em volta.
struct SiriOrb: View {
    var isActive: Bool
    var size: CGFloat = 64

    private static let colors: [Color] = [
        Color(red: 1.0, green: 0.27, blue: 0.55), Color(red: 0.62, green: 0.3, blue: 1.0),
        Color(red: 0.2, green: 0.5, blue: 1.0), Color(red: 0.2, green: 0.85, blue: 0.95),
        Color(red: 1.0, green: 0.27, blue: 0.55)
    ]

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: !isActive)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            ZStack {
                if isActive {
                    Circle()
                        .stroke(AngularGradient(colors: Self.colors, center: .center), lineWidth: max(1.5, size * 0.04))
                        .scaleEffect(1.08 + 0.1 * abs(sin(t * 2.6)))
                        .opacity(0.75 - 0.4 * abs(sin(t * 2.6)))
                }
                Circle()
                    .fill(AngularGradient(colors: Self.colors, center: .center,
                                          angle: .degrees(isActive ? t * 80 : 20)))
                // Escurece um pouco o centro para o ícone branco ter contraste.
                Circle()
                    .fill(RadialGradient(colors: [.black.opacity(0.35), .black.opacity(0.05)],
                                         center: .center, startRadius: 0, endRadius: size * 0.5))
                Circle()
                    .strokeBorder(Color.white.opacity(0.35), lineWidth: max(0.5, size * 0.015))
                Image(systemName: isActive ? "waveform" : "mic.fill")
                    .font(.system(size: size * 0.42, weight: .bold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.3), radius: 1, y: 0.5)
                    .symbolEffect(.variableColor.iterative, isActive: isActive)
                    .contentTransition(.symbolEffect(.replace))
            }
            .frame(width: size, height: size)
        }
        .accessibilityLabel(isActive ? "Ouvindo" : "Falar um comando")
    }
}

// MARK: - Informações de apps

enum AppInfo {
    private static var nameCache: [String: String] = [:]
    private static var iconCache: [String: NSImage] = [:]

    static func url(for bundleID: String) -> URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
    }

    static func name(for bundleID: String) -> String {
        if let cached = nameCache[bundleID] { return cached }
        var name = bundleID.split(separator: ".").last.map(String.init) ?? bundleID
        if let url = url(for: bundleID) {
            name = FileManager.default.displayName(atPath: url.path)
            if name.hasSuffix(".app") { name = String(name.dropLast(4)) }
        }
        nameCache[bundleID] = name
        return name
    }

    static func icon(for bundleID: String) -> NSImage {
        if let cached = iconCache[bundleID] { return cached }
        let icon: NSImage
        if let url = url(for: bundleID) {
            icon = NSWorkspace.shared.icon(forFile: url.path)
        } else {
            icon = NSImage(systemSymbolName: "app.fill", accessibilityDescription: nil) ?? NSImage()
        }
        iconCache[bundleID] = icon
        return icon
    }

    static func open(_ bundleID: String) {
        guard let url = url(for: bundleID) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration(), completionHandler: nil)
    }
}

// MARK: - Cursor de link

extension View {
    /// Mostra a mãozinha de link ao passar o mouse sobre algo clicável.
    func linkCursor(_ enabled: Bool = true) -> some View {
        modifier(LinkCursor(enabled: enabled))
    }
}

private struct LinkCursor: ViewModifier {
    let enabled: Bool

    func body(content: Content) -> some View {
        content.onContinuousHover { phase in
            guard enabled else { return }
            switch phase {
            case .active: NSCursor.pointingHand.set()
            case .ended: NSCursor.arrow.set()
            }
        }
    }
}

// MARK: - Funcionalidade desligada

/// Mostra o conteúdo quando a funcionalidade está ligada; senão, um aviso com um switch para ligar.
struct FeatureGate<Content: View>: View {
    let feature: Feature
    var compact = false
    @ViewBuilder var content: () -> Content
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var profiles = ProfileStore.shared

    var body: some View {
        if settings.isEnabled(feature) {
            content()
        } else if compact {
            FeatureOffGlance(feature: feature)
        } else {
            FeatureOffView(feature: feature)
        }
    }
}

private func featureSwitch(_ feature: Feature) -> some View {
    Toggle("", isOn: Binding(get: { AppSettings.shared.isEnabled(feature) },
                             set: { on in withAnimation(.island) { AppSettings.shared.setEnabled(feature, on) } }))
        .toggleStyle(.switch)
        .labelsHidden()
        .linkCursor()
        .help("Ligar \(feature.title)")
}

/// Página inteira de uma funcionalidade desligada.
struct FeatureOffView: View {
    let feature: Feature

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: feature.symbol)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(IslandStyle.secondary)
                .frame(width: 48, height: 48)
                .background(Circle().fill(IslandStyle.card))
            Text(feature.offTitle)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
            Text(feature.summary)
                .font(.system(size: 12))
                .foregroundStyle(IslandStyle.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
            HStack(spacing: 8) {
                Text("Ligar \(feature.title.lowercased())")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white)
                featureSwitch(feature).controlSize(.small)
            }
            .padding(.horizontal, 12).padding(.vertical, 5)
            .background(Capsule().fill(IslandStyle.card))
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Prévia de uma funcionalidade desligada.
struct FeatureOffGlance: View {
    let feature: Feature

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: feature.symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 38, height: 38)
                .background(Circle().fill(Color.white.opacity(0.15)))
            VStack(alignment: .leading, spacing: 1) {
                Text(feature.offTitle)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text("Ligue para usar na ilha")
                    .font(.system(size: 11))
                    .foregroundStyle(IslandStyle.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            featureSwitch(feature).controlSize(.small)
        }
    }
}
