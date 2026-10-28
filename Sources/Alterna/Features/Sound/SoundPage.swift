import SwiftUI

/// Página "Som": saída, volume geral e um mixer com o volume de cada app.
struct SoundPage: View {
    @ObservedObject private var mixer = SoundMixer.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            MasterRow()

            if let message = mixer.errorMessage {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
                    Text(message).lineLimit(2)
                    Spacer(minLength: 4)
                    CapsuleButton(title: "Permitir…") { mixer.openPrivacySettings() }
                }
                .font(.system(size: 11))
                .foregroundStyle(.yellow.opacity(0.9))
            }

            HStack {
                Text("Apps")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(IslandStyle.tertiary)
                Spacer()
                if !mixer.rules.isEmpty {
                    Button("Restaurar tudo") { mixer.resetAll() }
                        .buttonStyle(.plain)
                        .linkCursor()
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(IslandStyle.secondary)
                }
            }
            .padding(.horizontal, 8)

            if !mixer.supportsPerApp {
                IslandEmptyState(symbol: "speaker.badge.exclamationmark",
                                 title: "Volume por app indisponível",
                                 message: "O controle de som por app precisa do macOS 14.2 ou mais novo.")
            } else if mixer.apps.isEmpty {
                IslandEmptyState(symbol: "speaker.wave.2",
                                 title: "Nenhum app tocando som",
                                 message: "Quando um app tocar áudio, ele aparece aqui para você ajustar o volume, silenciar ou mandar para outra saída.")
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 2) {
                        ForEach(mixer.apps) { app in
                            AppSoundRow(app: app)
                        }
                    }
                    .padding(.bottom, 14)
                }
            }
        }
        .onAppear { mixer.refresh() }
    }
}

// MARK: - Volume geral e saída

private struct MasterRow: View {
    @ObservedObject private var mixer = SoundMixer.shared

    var body: some View {
        HStack(spacing: 10) {
            OutputMenu(selectedUID: mixer.defaultOutput?.uid, includeDefault: false, compact: false) { device in
                if let device { mixer.setDefaultOutput(device) }
            }

            RoundIconButton(symbol: Self.speakerSymbol(mixer.masterMuted ? 0 : mixer.masterVolume),
                            size: 28, help: mixer.masterMuted ? "Ativar som" : "Silenciar") {
                mixer.setMasterMuted(!mixer.masterMuted)
            }

            IslandSlider(value: Binding(get: { Double(mixer.masterMuted ? 0 : mixer.masterVolume) },
                                        set: { mixer.setMasterVolume(Float($0)) }),
                         tint: .white)
                .disabled(!mixer.canChangeMaster)
                .opacity(mixer.canChangeMaster ? 1 : 0.4)
                .help(mixer.canChangeMaster ? "Volume geral" : "Esta saída não permite mudar o volume pelo Mac")

            Text(percent(mixer.masterMuted ? 0 : mixer.masterVolume))
                .font(.system(size: 11, weight: .medium).monospacedDigit())
                .foregroundStyle(IslandStyle.secondary)
                .frame(width: 34, alignment: .trailing)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(IslandStyle.card))
    }

    static func speakerSymbol(_ volume: Float) -> String {
        switch volume {
        case ..<0.001: "speaker.slash.fill"
        case ..<0.34: "speaker.wave.1.fill"
        case ..<0.67: "speaker.wave.2.fill"
        default: "speaker.wave.3.fill"
        }
    }
}

private func percent(_ value: Float) -> String { "\(Int((value * 100).rounded()))%" }

// MARK: - Linha de um app

private struct AppSoundRow: View {
    let app: AudioApp
    @ObservedObject private var mixer = SoundMixer.shared
    @State private var hovering = false

    var body: some View {
        let rule = mixer.rule(for: app)
        let level = rule.muted ? 0 : rule.volume
        HStack(spacing: 10) {
            Image(nsImage: mixer.icon(for: app))
                .resizable()
                .interpolation(.high)
                .frame(width: 28, height: 28)
                .opacity(app.isPlaying ? 1 : 0.6)

            VStack(alignment: .leading, spacing: 1) {
                Text(app.name)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    if app.isPlaying && !rule.muted {
                        EqualizerBars(isPlaying: true, color: .white.opacity(0.6))
                            .scaleEffect(0.7, anchor: .leading)
                            .frame(width: 14, height: 10)
                    }
                    Text(status(rule))
                        .font(.system(size: 10))
                        .foregroundStyle(IslandStyle.tertiary)
                        .lineLimit(1)
                }
            }
            .frame(width: 128, alignment: .leading)

            RoundIconButton(symbol: rule.muted ? "speaker.slash.fill" : MasterRow.speakerSymbol(level),
                            size: 26, isOn: rule.muted,
                            help: rule.muted ? "Ativar som de \(app.name)" : "Silenciar \(app.name)") {
                mixer.toggleMute(app)
            }

            IslandSlider(value: Binding(get: { Double(level) }, set: { mixer.setVolume(Float($0), for: app) }),
                         tint: rule.muted ? .white.opacity(0.35) : .white)

            Text(percent(level))
                .font(.system(size: 11, weight: .medium).monospacedDigit())
                .foregroundStyle(IslandStyle.secondary)
                .frame(width: 34, alignment: .trailing)

            OutputMenu(selectedUID: rule.outputUID, includeDefault: true, compact: true) { device in
                mixer.setOutput(device?.uid, for: app)
            }

            Button {
                mixer.reset(app)
            } label: {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(IslandStyle.secondary)
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .linkCursor()
            .help("Voltar ao padrão")
            .opacity(rule.isDefault ? 0 : 1)
            .disabled(rule.isDefault)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(hovering ? IslandStyle.cardHover.opacity(0.6) : .clear))
        .onHover { hovering = $0 }
    }

    private func status(_ rule: AppSoundRule) -> String {
        var parts: [String] = []
        parts.append(rule.muted ? "Silenciado" : (app.isPlaying ? "Tocando" : "Em silêncio"))
        if let uid = rule.outputUID, let device = mixer.outputs.first(where: { $0.uid == uid }) {
            parts.append(device.name)
        }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Peças

/// Menu de saídas de áudio. `nil` = "Saída padrão do Mac".
private struct OutputMenu: View {
    let selectedUID: String?
    let includeDefault: Bool
    let compact: Bool
    let onSelect: (AudioOutputDevice?) -> Void
    @ObservedObject private var mixer = SoundMixer.shared

    var body: some View {
        let selected = selectedUID.flatMap { uid in mixer.outputs.first { $0.uid == uid } }
        Menu {
            if includeDefault {
                Button {
                    onSelect(nil)
                } label: {
                    if selectedUID == nil { Label("Saída padrão", systemImage: "checkmark") } else { Text("Saída padrão") }
                }
                Divider()
            }
            ForEach(mixer.outputs) { device in
                Button {
                    onSelect(device)
                } label: {
                    if device.uid == selectedUID { Label(device.name, systemImage: "checkmark") } else { Text(device.name) }
                }
            }
        } label: {
            if compact {
                Image(systemName: selected?.symbol ?? "hifispeaker.2")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(selected == nil ? IslandStyle.secondary : Color.accentColor)
            } else {
                Label(selected?.name ?? "Saída", systemImage: selected?.symbol ?? "hifispeaker.2")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)
            }
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(compact ? .hidden : .visible)
        .fixedSize()
        .frame(maxWidth: compact ? 30 : 170, alignment: .leading)
        .padding(.horizontal, compact ? 4 : 10)
        .padding(.vertical, compact ? 4 : 5)
        .background(Capsule().fill(compact ? Color.clear : IslandStyle.card))
        .linkCursor()
        .help(compact ? "Saída deste app: \(selected?.name ?? "padrão do Mac")" : "Saída de áudio do Mac")
    }
}

/// Barra de volume horizontal no estilo da Central de Controle.
struct IslandSlider: View {
    @Binding var value: Double
    var tint: Color = .white
    @State private var dragging = false
    @State private var hovering = false
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let clamped = min(max(value, 0), 1)
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.18))
                Capsule().fill(tint).frame(width: max(6, width * clamped))
                Circle()
                    .fill(.white)
                    .frame(width: 12, height: 12)
                    .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
                    .offset(x: min(max(width * clamped - 6, 0), width - 12))
                    .opacity(hovering || dragging ? 1 : 0)
            }
            .frame(height: hovering || dragging ? 6 : 5)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { drag in
                    guard isEnabled else { return }
                    dragging = true
                    value = min(max(drag.location.x / width, 0), 1)
                }
                .onEnded { _ in dragging = false })
            .onHover { hovering = $0 }
            .animation(.easeOut(duration: 0.12), value: hovering || dragging)
        }
        .frame(height: 18)
        .linkCursor(isEnabled)
    }
}
