import SwiftUI

private enum SidebarItem: Hashable {
    case general, music, notifications, voice, sound
    case profile(UUID)
}

/// Janela de Ajustes com barra lateral, como Ajustes do Sistema.
struct SettingsView: View {
    @EnvironmentObject private var store: ProfileStore
    @ObservedObject private var router = SettingsWindowController.shared
    @State private var selection: SidebarItem? = .general

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section {
                    Label("Geral", systemImage: "gearshape").tag(SidebarItem.general)
                    Label("Música", systemImage: "music.note").tag(SidebarItem.music)
                    Label("Notificações", systemImage: "bell.badge").tag(SidebarItem.notifications)
                    Label("Comando de voz", systemImage: "waveform").tag(SidebarItem.voice)
                    Label("Som", systemImage: "speaker.wave.2").tag(SidebarItem.sound)
                }

                Section(store.profilesEnabled ? "Perfis" : "Perfis (desligados)") {
                    ForEach(store.profiles) { profile in
                        Label(profile.name.isEmpty ? "Sem nome" : profile.name,
                              systemImage: profile.symbol)
                            .tag(SidebarItem.profile(profile.id))
                            .foregroundStyle(store.profilesEnabled ? .primary : .secondary)
                    }
                    .onMove { store.profiles.move(fromOffsets: $0, toOffset: $1) }
                }
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 210, max: 260)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                sidebarFooter
            }
        } detail: {
            detail
        }
        .frame(minWidth: 780, minHeight: 580)
        .onAppear(perform: openRequestedPane)
        .onChange(of: router.requestedPane) { _, _ in openRequestedPane() }
    }

    private func openRequestedPane() {
        switch router.requestedPane {
        case "music": selection = .music
        case "notifications": selection = .notifications
        case "voice": selection = .voice
        case "sound": selection = .sound
        case "general": selection = .general
        default: return
        }
        router.requestedPane = nil
    }

    @ViewBuilder
    private var detail: some View {
        switch selection {
        case .profile(let id):
            if let profileBinding = binding(for: id) {
                ProfileEditor(profile: profileBinding).id(id)
            } else {
                GeneralSettingsView()
            }
        case .music: MusicSettingsView()
        case .notifications: NotificationSettingsView()
        case .voice: VoiceSettingsView()
        case .sound: SoundSettingsView()
        default: GeneralSettingsView()
        }
    }

    private var sidebarFooter: some View {
        HStack(spacing: 0) {
            Button {
                let profile = store.addProfile()
                selection = .profile(profile.id)
            } label: {
                Image(systemName: "plus").frame(width: 26, height: 22)
            }
            .help("Novo perfil")

            Button {
                guard case .profile(let id) = selection else { return }
                selection = .general
                store.deleteProfile(id: id)
            } label: {
                Image(systemName: "minus").frame(width: 26, height: 22)
            }
            .help("Apagar perfil")
            .disabled(selectedProfileID == nil)

            Spacer()
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }

    private var selectedProfileID: UUID? {
        if case .profile(let id) = selection { return id }
        return nil
    }

    /// Binding por id (e não por índice) para não quebrar ao apagar/reordenar.
    private func binding(for id: UUID) -> Binding<Profile>? {
        guard let initial = store.profiles.first(where: { $0.id == id }) else { return nil }
        return Binding(
            get: { store.profiles.first(where: { $0.id == id }) ?? initial },
            set: { newValue in
                if let index = store.profiles.firstIndex(where: { $0.id == id }) {
                    store.profiles[index] = newValue
                }
            }
        )
    }
}

// MARK: - Geral

struct GeneralSettingsView: View {
    @EnvironmentObject private var store: ProfileStore
    @EnvironmentObject private var settings: AppSettings
    @ObservedObject private var notifications = NotificationMonitor.shared

    var body: some View {
        Form {
            Section {
                Picker("Tema", selection: $settings.islandTheme) {
                    ForEach(IslandTheme.allCases) { theme in
                        Text(theme.title).tag(theme)
                    }
                }
                .pickerStyle(.segmented)
                ThemePreview(theme: settings.islandTheme)
            } header: {
                Text("Aparência")
            } footer: {
                Text("Normal: preta, como a Dynamic Island do iPhone. Liquid Glass: vidro translúcido que desfoca o que está atrás. A parte em cima do notch continua preta para combinar com a câmera.")
            }

            Section {
                Toggle("Mostrar a Dynamic Island", isOn: $settings.showIsland)
                Toggle("Mostrar prévia ao passar o mouse", isOn: $settings.expandOnHover)
                Toggle("Inverter a roda lateral do mouse no carrossel", isOn: $settings.invertMouseCarousel)
                LabeledContent("Abrir e fechar a ilha") {
                    ShortcutRecorder(shortcut: $settings.islandShortcut)
                }
            } header: {
                Text("Dynamic Island")
            } footer: {
                Text("Passe o mouse no notch para ver a prévia e clique para abrir. Na ilha aberta, troque de seção pelo seletor no topo, deslizando dois dedos no trackpad, com a roda lateral do mouse (ou Shift + roda) ou com as setas ← →.")
            }

            Section {
                Toggle("Perfis de teclado", isOn: $store.profilesEnabled)
                if store.profilesEnabled {
                    Toggle("Mostrar aviso ao trocar de perfil", isOn: $store.showHUD)
                    LabeledContent("Ir para o próximo perfil") {
                        ShortcutRecorder(shortcut: $store.cycleShortcut)
                    }
                }
            } header: {
                Text("Alternar")
            } footer: {
                Text(store.profilesEnabled
                     ? "O atalho de cada perfil fica na página dele, na barra lateral."
                     : "Desligado: a seção Alternar da ilha mostra um aviso com um switch para ligar de novo, e os atalhos dos perfis ficam livres.")
            }

            Section {
                Toggle("Abrir ao iniciar sessão", isOn: $store.launchAtLogin)
            }

            Section {
                PermissionRow(title: "Acessibilidade",
                              detail: "Inverter só a roda do mouse.",
                              granted: store.accessibilityGranted) { store.requestAccessibility() }
                PermissionRow(title: "Acesso Total ao Disco",
                              detail: "Ler as notificações.",
                              granted: notifications.hasAccess) {
                    SettingsOpener.openSystemSettings("com.apple.preference.security?Privacy_AllFiles")
                }
                LabeledContent("Microfone e Fala") {
                    Button("Abrir…") {
                        SettingsOpener.openSystemSettings("com.apple.preference.security?Privacy_SpeechRecognition")
                    }
                }
                LabeledContent("Automação (Spotify)") {
                    Button("Abrir…") {
                        SettingsOpener.openSystemSettings("com.apple.preference.security?Privacy_Automation")
                    }
                }
            } header: {
                Text("Permissões")
            } footer: {
                Text("Depois de atualizar o Alterna, talvez o macOS peça essas permissões de novo. Se algo parar de funcionar, remova o Alterna da lista e adicione outra vez.")
            }

            Section {
                LabeledContent("Alterna") {
                    Button("Sair do Alterna") { NSApp.terminate(nil) }
                }
            } footer: {
                Text("Para voltar a estes Ajustes, use a engrenagem da ilha aberta ou abra o Alterna de novo em Aplicativos.")
            }

            Section("Agora no Mac") {
                LabeledContent("Fonte de entrada", value: store.currentInputSource?.name ?? "—")
                LabeledContent("Rolagem natural", value: ScrollDirection.isNatural ? "Ligada" : "Desligada")
                LabeledContent("Roda do mouse", value: store.reverseMouseWheel ? "Invertida" : "Igual ao trackpad")
                LabeledContent("Perfil ativo", value: store.activeProfile?.name ?? "Nenhum")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Geral")
        .onAppear { store.refreshStatus() }
    }
}

struct PermissionRow: View {
    let title: String
    let detail: String
    let granted: Bool
    let action: () -> Void

    var body: some View {
        LabeledContent {
            if granted {
                Label("Permitido", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Button("Permitir…", action: action)
            }
        } label: {
            Text(title)
            Text(detail)
        }
    }
}

/// Miniatura da ilha com o tema escolhido.
struct ThemePreview: View {
    let theme: IslandTheme

    var body: some View {
        HStack {
            Spacer()
            ZStack {
                LinearGradient(colors: [.purple, .pink, .orange], startPoint: .topLeading, endPoint: .bottomTrailing)
                    .frame(height: 96)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(spacing: 0) {
                    ZStack(alignment: .top) {
                        Group {
                            if theme == .glass {
                                ZStack {
                                    NotchShape(topRadius: 8, bottomRadius: 18).fill(.ultraThinMaterial)
                                    NotchShape(topRadius: 8, bottomRadius: 18).fill(Color.black.opacity(0.3))
                                    NotchShape(topRadius: 8, bottomRadius: 18)
                                        .stroke(Color.white.opacity(0.45), lineWidth: 1)
                                }
                            } else {
                                NotchShape(topRadius: 8, bottomRadius: 18).fill(Color.black)
                            }
                        }
                        .frame(width: 236, height: 62)
                        if theme == .glass {
                            UnevenRoundedRectangle(bottomLeadingRadius: 6, bottomTrailingRadius: 6, style: .continuous)
                                .fill(Color.black)
                                .frame(width: 70, height: 18)
                        }
                        HStack(spacing: 8) {
                            RoundedRectangle(cornerRadius: 5).fill(Color.white.opacity(0.85)).frame(width: 26, height: 26)
                            VStack(alignment: .leading, spacing: 3) {
                                Capsule().fill(Color.white.opacity(0.9)).frame(width: 80, height: 6)
                                Capsule().fill(Color.white.opacity(0.5)).frame(width: 54, height: 5)
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 22)
                        .padding(.top, 26)
                        .frame(width: 236)
                    }
                    Spacer(minLength: 0)
                }
                .frame(height: 96)
            }
            .frame(width: 320)
            .environment(\.colorScheme, .dark)
            .animation(.easeInOut(duration: 0.25), value: theme)
            Spacer()
        }
        .padding(.vertical, 4)
    }
}
