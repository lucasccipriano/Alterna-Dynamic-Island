import SwiftUI

/// Raiz da ilha: o corpo preto colado no topo da tela e o que aparece dentro dele.
struct IslandRootView: View {
    @ObservedObject private var model = IslandModel.shared
    @ObservedObject private var spotify = SpotifyController.shared
    @ObservedObject private var voice = VoiceController.shared
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        let size = model.bodySize
        let top = model.topRadius

        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                IslandBackground(topRadius: top, bottomRadius: model.bottomRadius,
                                 theme: settings.islandTheme, geometry: model.geometry)
                    .frame(width: size.width + top * 2, height: size.height)
                    .shadow(color: .black.opacity(model.isExpanded || model.isPreviewing || model.activity != nil ? 0.45 : 0),
                            radius: 18, y: 8)

                content
                    .frame(width: size.width, height: size.height, alignment: .top)
                    .clipShape(NotchShape(topRadius: 0, bottomRadius: model.bottomRadius))
            }
            .frame(width: size.width + top * 2, height: size.height)
            .contentShape(NotchShape(topRadius: top, bottomRadius: model.bottomRadius))

            Spacer(minLength: 0)
        }
        .frame(width: IslandController.canvas.width, height: IslandController.canvas.height, alignment: .top)
        .environment(\.colorScheme, .dark)
        .animation(.island, value: model.activity)
        .animation(.island, value: spotify.isPlaying)
        .animation(.island, value: voice.isListening)
    }

    @ViewBuilder
    private var content: some View {
        if model.isExpanded {
            ExpandedIslandView()
                .transition(.islandContent)
        } else if model.isPreviewing {
            IslandPreview()
                .transition(.islandContent)
        } else if let activity = model.activity {
            ActivityBanner(activity: activity)
                .transition(.islandContent)
        } else if model.showsVoiceActivity {
            CompactActivity(left: { SiriOrb(isActive: true, size: 18) },
                            right: { Image(systemName: "waveform").foregroundStyle(.white) })
                .transition(.islandContent)
        } else if model.showsMusicActivity {
            CompactActivity(left: {
                // Capa com folga em cima e embaixo (4 pt de cada lado), sem encostar nas bordas da ilha.
                let art = max(14, model.geometry.height - 8)
                ArtworkView(image: spotify.artwork, size: art, radius: art * 0.26)
            },
                            right: { EqualizerBars(isPlaying: spotify.isPlaying, color: spotify.accent) })
                .transition(.islandContent)
        } else {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { IslandController.shared.expand() }
                .linkCursor()
        }
    }
}

// MARK: - Forma do notch

/// Corpo com cantos de baixo arredondados e "abas" côncavas no topo,
/// para parecer que sai da moldura da tela.
struct NotchShape: Shape {
    var topRadius: CGFloat
    var bottomRadius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topRadius, bottomRadius) }
        set { topRadius = newValue.first; bottomRadius = newValue.second }
    }

    func path(in rect: CGRect) -> Path {
        let t = topRadius
        let b = min(bottomRadius, rect.height / 2, (rect.width - 2 * t) / 2)
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addQuadCurve(to: CGPoint(x: rect.minX + t, y: rect.minY + t),
                       control: CGPoint(x: rect.minX + t, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.minX + t, y: rect.maxY - b))
        p.addQuadCurve(to: CGPoint(x: rect.minX + t + b, y: rect.maxY),
                       control: CGPoint(x: rect.minX + t, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX - t - b, y: rect.maxY))
        p.addQuadCurve(to: CGPoint(x: rect.maxX - t, y: rect.maxY - b),
                       control: CGPoint(x: rect.maxX - t, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX - t, y: rect.minY + t))
        p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY),
                       control: CGPoint(x: rect.maxX - t, y: rect.minY))
        p.closeSubpath()
        return p
    }
}

// MARK: - Ilha compacta (atividade ao vivo)

/// Conteúdo dos dois lados do notch, como a atividade compacta do iPhone.
struct CompactActivity<Left: View, Right: View>: View {
    @ObservedObject private var model = IslandModel.shared
    @ViewBuilder var left: () -> Left
    @ViewBuilder var right: () -> Right

    var body: some View {
        let side = model.geometry.height + 10
        HStack(spacing: 0) {
            left().frame(width: side, height: model.geometry.height)
            Spacer(minLength: 0)
            right().frame(width: side, height: model.geometry.height)
        }
        .contentShape(Rectangle())
        .onTapGesture { IslandController.shared.expand() }
        .linkCursor()
    }
}

/// Barras de equalizador animadas.
struct EqualizerBars: View {
    var isPlaying: Bool
    var color: Color

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 24, paused: !isPlaying)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(alignment: .center, spacing: 2) {
                ForEach(0..<4, id: \.self) { i in
                    let phase = t * (5.0 + Double(i) * 1.3) + Double(i)
                    let level = isPlaying ? 0.35 + 0.65 * abs(sin(phase)) : 0.25
                    Capsule()
                        .fill(color)
                        .frame(width: 2.5, height: max(3, 13 * level))
                }
            }
            .frame(height: 14)
        }
    }
}

// MARK: - Banner

struct ActivityBanner: View {
    let activity: IslandActivity
    @ObservedObject private var model = IslandModel.shared

    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: model.geometry.height - 6)
            HStack(spacing: 12) {
                icon
                    .frame(width: 38, height: 38)
                VStack(alignment: .leading, spacing: 2) {
                    Text(activity.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(activity.subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.65))
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20)
            .frame(maxHeight: .infinity)
        }
        .contentShape(Rectangle())
        .linkCursor()
        .onTapGesture {
            if let action = activity.action {
                action()
                model.dismissActivity()
            } else {
                IslandController.shared.expand(to: activity.page)
            }
        }
    }

    @ViewBuilder
    private var icon: some View {
        switch activity.icon {
        case .symbol(let name, let color):
            Image(systemName: name)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(Circle().fill(color.gradient))
        case .app(let bundleID):
            AppIconView(bundleID: bundleID, size: 36)
        case .image(let image):
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 36, height: 36)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }
}

// MARK: - Ilha expandida

struct ExpandedIslandView: View {
    @ObservedObject private var model = IslandModel.shared
    @State private var appeared = false

    var body: some View {
        let g = model.geometry
        let size = model.bodySize
        let wing = max((size.width - g.width) / 2 - 22, 80)

        VStack(spacing: 0) {
            // Linha do notch: hora à esquerda, bateria à direita (como a barra de status).
            HStack(spacing: 0) {
                IslandClock()
                    .frame(width: wing, alignment: .leading)
                Spacer(minLength: g.width)
                IslandBatteryGlance()
                    .frame(width: wing, alignment: .trailing)
            }
            .padding(.horizontal, 22)
            .frame(height: g.height)

            // Seletor de seções à esquerda, Ajustes na extremidade direita.
            HStack(spacing: 8) {
                IslandTabBar()
                Spacer(minLength: 8)
                SettingsCircleButton()
            }
            .padding(.horizontal, 18)
            .padding(.top, 8)
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : -6)

            IslandCarousel()
                .padding(.top, 6)
                .padding(.bottom, 16)
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 10)
        }
        .onAppear {
            // Entrada em cascata: seletor primeiro, depois o conteúdo.
            withAnimation(.spring(response: 0.45, dampingFraction: 0.82).delay(0.12)) { appeared = true }
        }
    }
}

/// Segmented control da ilha: a seção ativa vira uma cápsula com ícone e nome;
/// as outras mostram só o ícone.
struct IslandTabBar: View {
    @ObservedObject private var model = IslandModel.shared
    @Namespace private var namespace

    var body: some View {
        HStack(spacing: 2) {
            ForEach(IslandPage.allCases) { page in
                TabItem(page: page, isActive: page == model.page, namespace: namespace) {
                    model.go(to: page)
                }
            }
        }
        .padding(3)
        .background(
            Capsule()
                .fill(Color.white.opacity(0.07))
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.06)))
        )
        .animation(.spring(response: 0.38, dampingFraction: 0.78), value: model.page)
    }

    private struct TabItem: View {
        let page: IslandPage
        let isActive: Bool
        let namespace: Namespace.ID
        let action: () -> Void
        @State private var hovering = false

        var body: some View {
            HStack(spacing: 6) {
                Image(systemName: page.symbol)
                    .font(.system(size: 12, weight: .semibold))
                    .fixedSize()
                    .frame(minWidth: 18)
                if isActive {
                    Text(page.title)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                        .fixedSize()
                        .transition(.opacity.combined(with: .scale(scale: 0.85, anchor: .leading)))
                }
            }
            .foregroundStyle(isActive ? Color.white : (hovering ? Color.white.opacity(0.85) : IslandStyle.secondary))
            .padding(.horizontal, isActive ? 16 : 9)
            .frame(height: 30)
            .background {
                if isActive {
                    Capsule()
                        .fill(Color.white.opacity(0.16))
                        .overlay(Capsule().strokeBorder(Color.white.opacity(0.14)))
                        .matchedGeometryEffect(id: "activeTab", in: namespace)
                } else if hovering {
                    Capsule().fill(Color.white.opacity(0.06))
                }
            }
            .contentShape(Capsule())
            .onHover { hovering = $0 }
            .linkCursor(!isActive)
            .onTapGesture(perform: action)
            .help(page.title)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(isActive ? [.isButton, .isSelected] : .isButton)
        }
    }
}

/// Botão redondo de Ajustes, na ponta direita do seletor.
/// Clique com o botão direito para sair do app.
struct SettingsCircleButton: View {
    @State private var hovering = false

    var body: some View {
        Button {
            SettingsOpener.open()
        } label: {
            Image(systemName: "gearshape.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(hovering ? Color.white : IslandStyle.secondary)
                .frame(width: 36, height: 36)
                .background(
                    Circle()
                        .fill(Color.white.opacity(hovering ? 0.14 : 0.07))
                        .overlay(Circle().strokeBorder(Color.white.opacity(0.06)))
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .linkCursor()
        .help("Ajustes do Alterna")
        .contextMenu {
            Button("Ajustes do Alterna…") { SettingsOpener.open() }
            Divider()
            Button("Sair do Alterna") { NSApp.terminate(nil) }
        }
    }
}

/// Hora na linha do notch.
struct IslandClock: View {
    var body: some View {
        TimelineView(.everyMinute) { context in
            Text(context.date, format: .dateTime.hour().minute())
                .font(.system(size: 13, weight: .semibold).monospacedDigit())
                .foregroundStyle(.white)
        }
    }
}

/// Bateria na linha do notch.
struct IslandBatteryGlance: View {
    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { _ in
            if let battery = SystemInfo.batteryLevel() {
                HStack(spacing: 5) {
                    Text("\(battery.percent)%")
                        .font(.system(size: 12, weight: .semibold).monospacedDigit())
                    Image(systemName: battery.symbol)
                        .font(.system(size: 14))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(battery.percent <= 20 && !battery.charging ? Color.red : Color.green)
                }
                .foregroundStyle(.white)
            }
        }
    }
}

// MARK: - Prévia (hover)

/// Prévia que aparece ao passar o mouse. Role (trackpad ou roda lateral) para ver
/// a prévia de outras seções; um clique abre a ilha por completo naquela seção.
struct IslandPreview: View {
    @ObservedObject private var model = IslandModel.shared
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: model.geometry.height - 2)

            ZStack {
                PreviewGlance(page: model.previewPage)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 2)
                    .id(model.previewPage)
                    .transition(.push(from: model.previewDirection))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 6)

            PreviewDots()
                .padding(.top, 2)
                .padding(.bottom, 9)
                .opacity(appeared ? 1 : 0)
        }
        .contentShape(Rectangle())
        .linkCursor()
        .onTapGesture { IslandController.shared.expand(to: model.previewPage) }
        .help("Clique para abrir · role para ver outras seções")
        .onAppear {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.85).delay(0.06)) { appeared = true }
        }
    }
}

/// Indicador das prévias (as bolinhas do carrossel), clicável.
private struct PreviewDots: View {
    @ObservedObject private var model = IslandModel.shared

    var body: some View {
        HStack(spacing: 5) {
            ForEach(IslandPage.allCases) { page in
                let active = page == model.previewPage
                Capsule()
                    .fill(Color.white.opacity(active ? 0.9 : 0.25))
                    .frame(width: active ? 14 : 5, height: 5)
                    .contentShape(Rectangle().inset(by: -4))
                    .onTapGesture { model.goPreview(to: page) }
                    .linkCursor(!active)
                    .help(page.title)
            }
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.75), value: model.previewPage)
    }
}

/// Resumo de uma seção, em uma linha.
private struct PreviewGlance: View {
    let page: IslandPage
    @ObservedObject private var spotify = SpotifyController.shared
    @ObservedObject private var store = ProfileStore.shared
    @ObservedObject private var notifications = NotificationMonitor.shared
    @ObservedObject private var bluetooth = BluetoothManager.shared
    @ObservedObject private var mixer = SoundMixer.shared
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var wake = WakeWordListener.shared

    var body: some View {
        Group {
            switch page {
            case .music: music
            case .notifications: notificationsGlance
            case .voice: voice
            case .profiles: profiles
            case .bluetooth: bluetoothGlance
            case .sound: soundGlance
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // Música
    @ViewBuilder private var music: some View {
        if spotify.isRunning, let track = spotify.track {
            HStack(spacing: 12) {
                ArtworkView(image: spotify.artwork, size: 40, radius: 9)
                titles(track.name, track.artist)
                Spacer(minLength: 8)
                RoundIconButton(symbol: "backward.fill", size: 28, help: "Anterior") { spotify.previous() }
                RoundIconButton(symbol: spotify.isPlaying ? "pause.fill" : "play.fill", size: 32,
                                help: spotify.isPlaying ? "Pausar" : "Tocar") { spotify.playPause() }
                RoundIconButton(symbol: "forward.fill", size: 28, help: "Próxima") { spotify.next() }
                EqualizerBars(isPlaying: spotify.isPlaying, color: spotify.accent)
                    .frame(width: 18)
            }
        } else {
            row(icon: badge("music.note", .green),
                title: spotify.isRunning ? "Nada tocando" : "Spotify fechado",
                subtitle: "Clique para abrir a música")
        }
    }

    // Notificações
    @ViewBuilder private var notificationsGlance: some View {
        if let latest = notifications.visibleItems.first {
            let count = notifications.visibleItems.filter { Date().timeIntervalSince($0.date) < 3600 }.count
            HStack(spacing: 12) {
                AppIconView(bundleID: latest.bundleID, size: 36)
                titles(latest.title.isEmpty ? latest.appName : latest.title,
                       [latest.subtitle, latest.body].filter { !$0.isEmpty }.joined(separator: " — "))
                Spacer(minLength: 8)
                if count > 0 {
                    Text("\(count)")
                        .font(.system(size: 12, weight: .bold).monospacedDigit())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .frame(height: 22)
                        .background(Capsule().fill(Color.red))
                        .help("Na última hora")
                }
            }
        } else {
            row(icon: badge("bell.fill", .red),
                title: notifications.hasAccess ? "Tudo em dia" : "Notificações",
                subtitle: notifications.hasAccess ? "Nenhuma notificação nova" : "Dê Acesso Total ao Disco nos Ajustes")
        }
    }

    // Comando de voz
    private var voice: some View {
        let listening = wake.state == .capturing || wake.state == .running
        return HStack(spacing: 12) {
            Button {
                IslandController.shared.startVoice()
            } label: {
                SiriOrb(isActive: listening, size: 38)
            }
            .buttonStyle(.plain)
            .linkCursor()
            .help("Falar um comando")

            if listening {
                // Mostra ao vivo o que está sendo dito depois de "Alt".
                VStack(alignment: .leading, spacing: 1) {
                    Text(wake.state == .running ? "Executando…" : "Ouvindo…")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(IslandStyle.secondary)
                    Text(wake.command.isEmpty ? "Diga o comando" : "“\(wake.command)”")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(wake.command.isEmpty ? IslandStyle.tertiary : .white)
                        .lineLimit(1)
                        .truncationMode(.head)
                        .contentTransition(.interpolate)
                        .animation(.easeOut(duration: 0.15), value: wake.command)
                }
            } else {
                titles("Comando de voz",
                       wake.isActive ? "Diga “\(settings.wakeWord)” e o comando"
                                     : "Clique e fale" + (settings.voiceShortcut.map { " · \($0.display)" } ?? ""))
            }
            Spacer()
            WakeMicToggle(size: 30)
        }
    }

    // Alternar
    @ViewBuilder
    private var profiles: some View {
        if !store.profilesEnabled {
            HStack(spacing: 12) {
                badge("keyboard", .gray)
                titles("Perfis de teclado desligados", "Ligue para trocar de perfil")
                Spacer(minLength: 8)
                Toggle("", isOn: Binding(get: { store.profilesEnabled },
                                         set: { on in withAnimation(.island) { store.profilesEnabled = on } }))
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .labelsHidden()
                    .linkCursor()
                    .help("Ligar perfis de teclado")
            }
        } else {
            profilesGlance
        }
    }

    private var profilesGlance: some View {
        HStack(spacing: 12) {
            badge(store.activeProfile?.symbol ?? "switch.2", .accentColor)
            titles(store.activeProfile?.name ?? "Nenhum perfil ativo",
                   store.currentInputSource?.name ?? "Teclado")
            Spacer(minLength: 8)
            // Troca de perfil direto da prévia.
            HStack(spacing: 6) {
                ForEach(store.profiles.prefix(4)) { profile in
                    let active = profile.id == store.activeProfileID
                    Button {
                        store.apply(profile)
                    } label: {
                        Image(systemName: profile.symbol)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 30, height: 30)
                            .background(Circle().fill(active ? Color.accentColor : Color.white.opacity(0.12)))
                    }
                    .buttonStyle(.plain)
                    .linkCursor(!active)
                    .help("Aplicar \(profile.name)")
                }
            }
        }
    }

    // Bluetooth
    private var bluetoothGlance: some View {
        let connected = bluetooth.paired.filter(\.isConnected)
        return HStack(spacing: 12) {
            badge("antenna.radiowaves.left.and.right", bluetooth.isPoweredOn ? .blue : .gray)
            titles(bluetooth.isPoweredOn ? "Bluetooth ligado" : "Bluetooth desligado",
                   connected.isEmpty ? (bluetooth.isPoweredOn ? "Nenhum dispositivo conectado" : "Clique para abrir")
                                     : connected.map(\.name).joined(separator: ", "))
            Spacer(minLength: 8)
            HStack(spacing: -6) {
                ForEach(connected.prefix(3)) { device in
                    Image(systemName: device.symbol)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(Color.blue).overlay(Circle().strokeBorder(.black, lineWidth: 2)))
                }
            }
        }
        .onAppear { bluetooth.refresh() }
    }

    // Som
    private var soundGlance: some View {
        let playing = mixer.playingApps
        let level = mixer.masterMuted ? 0 : mixer.masterVolume
        return HStack(spacing: 12) {
            badge(level < 0.001 ? "speaker.slash.fill" : "speaker.wave.2.fill", .pink)
            titles(mixer.defaultOutput?.name ?? "Som",
                   playing.isEmpty ? "Nenhum app tocando" : playing.map(\.name).prefix(3).joined(separator: ", "))
            Spacer(minLength: 8)
            Button {
                mixer.setMasterMuted(!mixer.masterMuted)
            } label: {
                Image(systemName: mixer.masterMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(Color.white.opacity(0.12)))
            }
            .buttonStyle(.plain)
            .linkCursor()
            .help(mixer.masterMuted ? "Ativar som" : "Silenciar")
            IslandSlider(value: Binding(get: { Double(level) }, set: { mixer.setMasterVolume(Float($0)) }))
                .frame(width: 110)
                .disabled(!mixer.canChangeMaster)
        }
        .onAppear { mixer.refresh() }
    }

    // Peças
    private func titles(_ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
            if !subtitle.isEmpty {
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(IslandStyle.secondary)
                    .lineLimit(1)
            }
        }
    }

    private func badge(_ symbol: String, _ color: Color) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 38, height: 38)
            .background(Circle().fill(color.gradient))
    }

    private func row(icon: some View, title: String, subtitle: String) -> some View {
        HStack(spacing: 12) {
            icon
            titles(title, subtitle)
            Spacer()
        }
    }
}

struct IslandCarousel: View {
    @ObservedObject private var model = IslandModel.shared

    var body: some View {
        ZStack {
            page(model.page)
                // Margem dentro da área recortada: sombras, anéis e destaques não são cortados.
                .padding(.horizontal, 18)
                .padding(.top, 6)
                .padding(.bottom, 6)
                .id(model.page)
                .transition(.push(from: model.direction))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .clipped()
        // Esmaece a borda de baixo em vez de cortar o conteúdo na curva da ilha.
        .mask {
            VStack(spacing: 0) {
                Color.black
                LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                    .frame(height: 18)
            }
        }
    }

    @ViewBuilder
    private func page(_ page: IslandPage) -> some View {
        switch page {
        case .music: MusicPage()
        case .notifications: NotificationsPage()
        case .voice: VoicePage()
        case .profiles: ProfilesPage()
        case .bluetooth: BluetoothPage()
        case .sound: SoundPage()
        }
    }
}

// MARK: - Transição do conteúdo

/// O conteúdo surge depois que a forma começa a crescer (desfoque + escala),
/// e some rápido antes de a forma encolher, como na Dynamic Island.
struct IslandContentFade: ViewModifier {
    let active: Bool

    func body(content: Content) -> some View {
        content
            .opacity(active ? 0 : 1)
            .blur(radius: active ? 10 : 0)
            .scaleEffect(active ? 0.9 : 1, anchor: .top)
    }
}

extension AnyTransition {
    static var islandContent: AnyTransition {
        .asymmetric(
            insertion: .modifier(active: IslandContentFade(active: true), identity: IslandContentFade(active: false))
                .animation(.spring(response: 0.42, dampingFraction: 0.86).delay(0.09)),
            removal: .modifier(active: IslandContentFade(active: true), identity: IslandContentFade(active: false))
                .animation(.easeOut(duration: 0.12))
        )
    }
}

// MARK: - Fundo (Normal ou Liquid Glass)

struct IslandBackground: View {
    let topRadius: CGFloat
    let bottomRadius: CGFloat
    let theme: IslandTheme
    let geometry: NotchGeometry

    var body: some View {
        let shape = NotchShape(topRadius: topRadius, bottomRadius: bottomRadius)
        switch theme {
        case .normal:
            shape.fill(Color.black)
        case .glass:
            ZStack(alignment: .top) {
                // Desfoque do que está atrás da ilha (a área de trabalho e as janelas).
                BehindWindowBlur()
                    .clipShape(shape)
                // Tinta escura para manter o texto legível sobre qualquer fundo.
                shape.fill(Color.black.opacity(0.32))
                // Brilho de vidro: luz vinda de cima e borda especular.
                shape.fill(LinearGradient(colors: [.white.opacity(0.14), .white.opacity(0.02), .clear],
                                          startPoint: .top, endPoint: .bottom))
                shape.stroke(LinearGradient(colors: [.white.opacity(0.55), .white.opacity(0.1), .white.opacity(0.3)],
                                            startPoint: .topLeading, endPoint: .bottomTrailing),
                             lineWidth: 1)
                // O notch físico é preto: mantém essa parte preta para não aparecer o "recorte".
                if geometry.hasNotch {
                    UnevenRoundedRectangle(bottomLeadingRadius: geometry.height * 0.3,
                                           bottomTrailingRadius: geometry.height * 0.3,
                                           style: .continuous)
                        .fill(Color.black)
                        .frame(width: geometry.width, height: geometry.height)
                }
            }
        }
    }
}

/// NSVisualEffectView que desfoca o que está atrás da janela.
struct BehindWindowBlur: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        view.appearance = NSAppearance(named: .vibrantDark)
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

// MARK: - Botão do microfone do "Alt"

/// Liga/desliga a escuta da palavra de ativação (microfone sempre aberto).
struct WakeMicToggle: View {
    var size: CGFloat = 30
    @ObservedObject private var settings = AppSettings.shared
    @State private var hovering = false

    var body: some View {
        let on = settings.wakeWordEnabled
        Button {
            withAnimation(.island) { settings.wakeWordEnabled.toggle() }
        } label: {
            Image(systemName: on ? "mic.fill" : "mic.slash.fill")
                .font(.system(size: size * 0.42, weight: .semibold))
                .foregroundStyle(on ? Color.white : Color.white.opacity(0.7))
                .frame(width: size, height: size)
                .background(Circle().fill(on ? Color.orange.opacity(hovering ? 0.95 : 0.8)
                                             : Color.white.opacity(hovering ? 0.2 : 0.12)))
                .contentShape(Circle())
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .linkCursor()
        .help(on ? "Desligar o microfone (parar de ouvir “\(settings.wakeWord)”)"
                 : "Ligar o microfone para ouvir “\(settings.wakeWord)”")
    }
}
