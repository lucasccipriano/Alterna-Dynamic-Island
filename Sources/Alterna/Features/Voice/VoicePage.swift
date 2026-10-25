import AppKit
import SwiftUI

/// Página de comando de voz: esfera da Siri, transcrição, campo de texto e resultado.
struct VoicePage: View {
    @ObservedObject private var voice = VoiceController.shared
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var wake = WakeWordListener.shared
    @State private var typed = ""

    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(spacing: 8) {
                Button {
                    voice.toggle()
                } label: {
                    SiriOrb(isActive: voice.isListening || wake.state == .capturing, size: 86)
                        .scaleEffect(voice.isListening ? 1 + CGFloat(voice.level) * 0.12 : 1)
                        .animation(.easeOut(duration: 0.12), value: voice.level)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .linkCursor()
                .help(voice.isListening ? "Parar e executar" : "Falar um comando")

                Text(voice.isListening ? "Ouvindo…" : (voice.isWorking ? "Executando…" : "Toque para falar"))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(IslandStyle.secondary)
                if let shortcut = settings.voiceShortcut, !voice.isListening {
                    Text(shortcut.display)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(IslandStyle.tertiary)
                }
                // Escuta da palavra de ativação ("Alt").
                HStack(spacing: 6) {
                    WakeMicToggle(size: 24)
                    Text(wakeStatus)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(IslandStyle.tertiary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 2)
            }
            .frame(width: 110)
            .padding(.top, 4)

            VStack(alignment: .leading, spacing: 8) {
                IslandSearchField(prompt: "Digite ou fale: abrir Safari, pesquisar contrato…",
                                  text: $typed, symbol: "text.cursor") {
                    voice.run(typed)
                    typed = ""
                }

                if voice.isListening || (!voice.transcript.isEmpty && voice.result == nil) {
                    Text(voice.transcript.isEmpty ? "Fale agora…" : "“\(voice.transcript)”")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(voice.transcript.isEmpty ? IslandStyle.tertiary : .white)
                        .lineLimit(3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else if let error = voice.errorMessage {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.yellow)
                } else if let result = voice.result {
                    if !voice.transcript.isEmpty {
                        Text("“\(voice.transcript)”")
                            .font(.system(size: 11))
                            .foregroundStyle(IslandStyle.tertiary)
                            .lineLimit(1)
                    }
                    ResultView(result: result)
                } else {
                    Suggestions { voice.run($0) }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

extension VoicePage {
    fileprivate var wakeStatus: String {
        switch wake.state {
        case .off: "Microfone desligado"
        case .paused: wake.errorMessage == nil ? "Em pausa" : "Sem permissão"
        case .waiting: "Diga “\(settings.wakeWord)”"
        case .capturing: "Ouvindo…"
        case .running: "Executando…"
        }
    }
}

// MARK: - Sugestões

private struct Suggestions: View {
    let run: (String) -> Void
    private let examples = ["Abrir Safari", "Abrir a pasta Downloads", "Pesquisar contrato",
                            "Pesquisar na internet clima em Lisboa", "Bateria", "Armazenamento", "Tocar Coldplay"]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Experimente")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(IslandStyle.tertiary)
            FlowLayout(spacing: 6) {
                ForEach(examples, id: \.self) { example in
                    CapsuleButton(title: example) { run(example) }
                }
            }
            Text("Com a Siri: crie o Atalho \"Alterna\" (veja em Ajustes › Comando de voz) e diga \"E aí Siri, Alterna\".")
                .font(.system(size: 10))
                .foregroundStyle(IslandStyle.tertiary)
                .padding(.top, 2)
        }
    }
}

/// Distribui itens em linhas, quebrando quando não cabem.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 400
        var x: CGFloat = 0, y: CGFloat = 0, row: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > width, x > 0 { x = 0; y += row + spacing; row = 0 }
            x += size.width + spacing
            row = max(row, size.height)
        }
        return CGSize(width: width, height: y + row)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, row: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX { x = bounds.minX; y += row + spacing; row = 0 }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            row = max(row, size.height)
        }
    }
}

// MARK: - Resultado

private struct ResultView: View {
    let result: CommandResult

    var body: some View {
        switch result {
        case .opened(let name, let url, let detail):
            HStack(spacing: 12) {
                if let url {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                        .resizable().frame(width: 40, height: 40)
                } else {
                    symbolBadge("globe", .blue)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(name).font(.system(size: 14, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                    Text(detail).font(.system(size: 12)).foregroundStyle(IslandStyle.secondary)
                }
            }
            .padding(.top, 4)

        case .info(let symbol, let title, let value, let detail):
            HStack(spacing: 14) {
                Image(systemName: symbol)
                    .font(.system(size: 30, weight: .medium))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.green)
                    .frame(width: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 12, weight: .medium)).foregroundStyle(IslandStyle.secondary)
                    Text(value).font(.system(size: 24, weight: .semibold, design: .rounded)).foregroundStyle(.white)
                        .lineLimit(1).minimumScaleFactor(0.6)
                    if let detail {
                        Text(detail).font(.system(size: 11)).foregroundStyle(IslandStyle.tertiary).lineLimit(2)
                    }
                }
            }
            .padding(.top, 4)

        case .music(let title, let detail):
            HStack(spacing: 12) {
                symbolBadge("music.note", .green)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 14, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                    if !detail.isEmpty {
                        Text(detail).font(.system(size: 12)).foregroundStyle(IslandStyle.secondary).lineLimit(2)
                    }
                }
            }
            .padding(.top, 4)

        case .message(let symbol, let title, let detail, let webQuery):
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    symbolBadge(symbol, .orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title).font(.system(size: 14, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                        Text(detail).font(.system(size: 12)).foregroundStyle(IslandStyle.secondary).lineLimit(2)
                    }
                }
                if let webQuery {
                    CapsuleButton(title: "Pesquisar na internet", symbol: "globe") {
                        CommandEngine.openWeb(webQuery)
                    }
                }
            }
            .padding(.top, 4)

        case .items(let title, let items, let webQuery):
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(title)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(IslandStyle.tertiary)
                        .lineLimit(1)
                    Spacer()
                    if let webQuery {
                        Button {
                            CommandEngine.openWeb(webQuery)
                        } label: {
                            Label("Internet", systemImage: "globe")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(IslandStyle.secondary)
                        }
                        .buttonStyle(.plain)
                        .linkCursor()
                    }
                }
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 0) {
                        ForEach(items) { item in
                            HoverRow(action: { NSWorkspace.shared.open(item.url) }) {
                                HStack(spacing: 10) {
                                    Image(nsImage: NSWorkspace.shared.icon(forFile: item.url.path))
                                        .resizable().frame(width: 22, height: 22)
                                    Text(item.name)
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundStyle(.white)
                                        .lineLimit(1)
                                    Spacer()
                                    Text(item.kind)
                                        .font(.system(size: 11))
                                        .foregroundStyle(IslandStyle.tertiary)
                                        .lineLimit(1)
                                }
                            }
                            .contextMenu {
                                Button("Abrir") { NSWorkspace.shared.open(item.url) }
                                Button("Mostrar no Finder") { NSWorkspace.shared.activateFileViewerSelecting([item.url]) }
                            }
                        }
                    }
                }
            }
        }
    }

    private func symbolBadge(_ name: String, _ color: Color) -> some View {
        Image(systemName: name)
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 38, height: 38)
            .background(Circle().fill(color.gradient))
    }
}
