import AVFoundation
import AppKit
import Speech
import SwiftUI

// MARK: - Música

struct MusicSettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @ObservedObject private var api = SpotifyAPI.shared
    @ObservedObject private var spotify = SpotifyController.shared

    var body: some View {
        Form {
            Section {
                LabeledContent("App do Spotify") {
                    Text(spotify.isRunning ? "Aberto" : "Fechado")
                        .foregroundStyle(.secondary)
                }
                Toggle("Mostrar capa e equalizador no notch enquanto toca", isOn: $settings.musicLiveActivity)
            } header: {
                Text("Player")
            } footer: {
                Text("Tocar, pausar, pular, aleatório, repetir e volume funcionam sem login. Na primeira vez, o macOS pede para o Alterna controlar o Spotify.")
            }

            Section {
                if api.isConnected {
                    LabeledContent("Conta") {
                        HStack {
                            Text(api.userName ?? "Conectada")
                            Button("Desconectar") { api.disconnect() }
                        }
                    }
                } else {
                    TextField("Client ID", text: $api.clientID, prompt: Text("Cole aqui o Client ID"))
                    LabeledContent("Conta") {
                        SpotifyLoginButton()
                    }
                }
                if let error = api.errorMessage {
                    Text(error).foregroundStyle(.red).font(.callout)
                }
            } header: {
                Text("Playlists e busca")
            } footer: {
                Text("Para listar suas playlists e buscar músicas dentro da ilha, o Spotify exige um app de desenvolvedor (gratuito). Desde 2026, a conta dona do app precisa ser Premium.")
            }

            if !api.isConnected {
                Section("Como criar o app do Spotify (uma vez só)") {
                    Step(number: 1) {
                        HStack {
                            Text("Abra o painel de desenvolvedor e clique em **Create app**.")
                            Spacer()
                            Button("Abrir painel") {
                                NSWorkspace.shared.open(URL(string: "https://developer.spotify.com/dashboard")!)
                            }
                        }
                    }
                    Step(number: 2) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Em **Redirect URIs**, adicione exatamente:")
                            CopyField(text: SpotifyAPI.redirectURI)
                        }
                    }
                    Step(number: 3) { Text("Marque **Web API**, aceite os termos e salve.") }
                    Step(number: 4) { Text("Em **Settings**, copie o **Client ID** e cole no campo acima.") }
                    Step(number: 5) { Text("Clique em **Entrar com o Spotify** e autorize no navegador.") }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Música")
    }
}

// MARK: - Notificações

struct NotificationSettingsView: View {
    @ObservedObject private var monitor = NotificationMonitor.shared

    var body: some View {
        Form {
            Section {
                PermissionRow(title: "Acesso Total ao Disco",
                              detail: "Necessário para ler a Central de Notificações.",
                              granted: monitor.hasAccess) {
                    SettingsOpener.openSystemSettings("com.apple.preference.security?Privacy_AllFiles")
                }
                Toggle("Mostrar banner na ilha quando chegar uma notificação", isOn: $monitor.showBanners)
            } footer: {
                Text("O macOS não oferece uma forma oficial de outros apps lerem notificações, então o Alterna lê uma cópia do banco da Central de Notificações. Isso pode mudar numa atualização do macOS. Os banners do próprio macOS continuam aparecendo; para desligá-los, use Ajustes do Sistema › Notificações.")
            }

            Section("Tipos de notificação") {
                ForEach(NotificationCategory.allCases) { category in
                    Toggle(isOn: Binding(get: { !monitor.disabledCategories.contains(category) },
                                         set: { monitor.setCategory(category, enabled: $0) })) {
                        Label {
                            Text(category.title)
                        } icon: {
                            Image(systemName: category.symbol)
                                .foregroundStyle(.white)
                                .frame(width: 20, height: 20)
                                .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(category.color.gradient))
                        }
                    }
                }
            }

            Section {
                if monitor.knownApps.isEmpty {
                    Text("Os apps aparecem aqui quando mandarem a primeira notificação.")
                        .foregroundStyle(.secondary)
                }
                ForEach(monitor.knownApps, id: \.self) { bundleID in
                    let category = NotificationCategory.of(bundleID)
                    let categoryOn = !monitor.disabledCategories.contains(category)
                    Toggle(isOn: Binding(get: { !monitor.disabledApps.contains(bundleID) },
                                         set: { monitor.setApp(bundleID, enabled: $0) })) {
                        HStack(spacing: 8) {
                            AppIconView(bundleID: bundleID, size: 20)
                            VStack(alignment: .leading, spacing: 0) {
                                Text(AppInfo.name(for: bundleID))
                                Text(categoryOn ? category.title : "\(category.title) (tipo desligado)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .disabled(!categoryOn)
                }
            } header: {
                Text("Por app")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Notificações")
    }
}

// MARK: - Comando de voz

struct VoiceSettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @State private var test = "bateria"

    var body: some View {
        Form {
            Section {
                Picker("Idioma", selection: $settings.voiceLocale) {
                    ForEach(AppSettings.voiceLocales, id: \.id) { locale in
                        Text(locale.name).tag(locale.id)
                    }
                }
                LabeledContent("Atalho para falar") {
                    ShortcutRecorder(shortcut: $settings.voiceShortcut)
                }
                LabeledContent("Testar um comando") {
                    HStack {
                        TextField("", text: $test).frame(width: 220)
                        Button("Executar") { IslandController.shared.runCommand(test) }
                    }
                }
            } header: {
                Text("Reconhecimento de fala")
            } footer: {
                Text("Exemplos: \"abrir Safari\", \"abrir a pasta Downloads\", \"pesquisar contrato\", \"pesquisar na internet clima em Lisboa\", \"tocar Coldplay\", \"bateria\", \"armazenamento\", \"versão do macOS\".")
            }

            Section {
                Toggle("Ouvir a palavra de ativação", isOn: $settings.wakeWordEnabled)
                LabeledContent("Palavra de ativação") {
                    TextField("", text: $settings.wakeWord, prompt: Text("Alt"))
                        .frame(width: 140)
                        .multilineTextAlignment(.trailing)
                }
                Toggle("Só quando o Mac estiver na tomada", isOn: $settings.wakeWordOnlyOnPower)
                LabeledContent("Estado") {
                    WakeStatusLabel()
                }
                DisclosureGroup("Diagnóstico") {
                    VoiceDiagnostics()
                }
            } header: {
                Text("Ativação por voz")
            } footer: {
                Text("Diga \"\(settings.wakeWord), abrir navegador\" ou \"\(settings.wakeWord)… pesquisar contrato\". Ao ouvir a palavra, a prévia da ilha abre mostrando o que você está falando. Com isso ligado, o microfone fica aberto e o macOS mostra o ponto laranja na barra de menus. O reconhecimento roda no próprio Mac quando o idioma permite. Desligue aqui ou pelo botão de microfone na ilha.")
            }

            Section {
                Step(number: 1) {
                    HStack {
                        Text("Abra o app **Atalhos** e crie um atalho novo (**+**).")
                        Spacer()
                        Button("Abrir Atalhos") {
                            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.shortcuts") {
                                NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration(), completionHandler: nil)
                            }
                        }
                    }
                }
                Step(number: 2) { Text("Dê o nome **Alterna** ao atalho.") }
                Step(number: 3) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Adicione a ação **Abrir URLs** com este endereço:")
                        CopyField(text: "alterna://ouvir")
                    }
                }
                Step(number: 4) { Text("Diga **\"E aí Siri, Alterna\"**. A ilha abre ouvindo; aí é só falar o comando.") }
            } header: {
                Text("Usar com a Siri")
            } footer: {
                Text("Quer falar tudo de uma vez para a Siri? Monte o atalho com as ações **Ditar Texto** e **Abrir URLs** usando alterna://comando?texto= seguido da variável **Texto Ditado**.")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Comando de voz")
    }
}

// MARK: - Peças

private struct Step<Content: View>: View {
    let number: Int
    @ViewBuilder var content: () -> Content

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(number)")
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 18, height: 18)
                .background(Circle().fill(Color.accentColor))
            content()
        }
    }
}

private struct CopyField: View {
    let text: String
    @State private var copied = false

    var body: some View {
        HStack {
            Text(text)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
            Spacer()
            Button(copied ? "Copiado" : "Copiar") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
                copied = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.12)))
    }
}

private struct WakeStatusLabel: View {
    @ObservedObject private var wake = WakeWordListener.shared

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(text).foregroundStyle(.secondary)
        }
    }

    private var text: String {
        if let error = wake.errorMessage, wake.state == .paused { return error }
        switch wake.state {
        case .off: return "Desligado"
        case .paused: return "Em pausa"
        case .waiting: return "Ouvindo a palavra de ativação"
        case .capturing: return "Ouvindo o comando…"
        case .running: return "Executando…"
        }
    }

    private var color: Color {
        switch wake.state {
        case .off: .gray
        case .paused: .yellow
        default: .green
        }
    }
}

/// Mostra o que está acontecendo com o microfone e o reconhecimento de fala.
private struct VoiceDiagnostics: View {
    @ObservedObject private var wake = WakeWordListener.shared
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            row("Permissão de fala", speechStatus)
            row("Permissão de microfone", micStatus)
            row("Idioma", settings.voiceLocale)
            row("Reconhecimento no próprio Mac", wake.onDevice ? "Sim" : "Não (usa a internet)")
            row("Microfone em uso", wake.usingBuiltInMic ? "Microfone do Mac" : "Microfone padrão do sistema")
            row("Áudio chegando", wake.audioReceived ? "Sim" : "Não")
            row("Última frase ouvida", wake.lastHeard.isEmpty ? "—" : "“\(wake.lastHeard)”")
            if let error = wake.lastRecognitionError {
                row("Último erro", error)
            }
            if let error = wake.errorMessage {
                row("Aviso", error)
            }
            HStack {
                Button("Reiniciar escuta") { wake.restartNow() }
                Button("Ajustes de Ditado e Siri…") {
                    SettingsOpener.openSystemSettings("com.apple.Siri-Settings.extension")
                }
            }
            .padding(.top, 4)
        }
        .font(.callout)
        .padding(.vertical, 4)
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).foregroundStyle(.secondary)
            Spacer()
            Text(value).multilineTextAlignment(.trailing).textSelection(.enabled)
        }
    }

    private var speechStatus: String {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized: "Permitida"
        case .denied: "Negada"
        case .restricted: "Restrita"
        case .notDetermined: "Ainda não pedida"
        @unknown default: "Desconhecida"
        }
    }

    private var micStatus: String {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: "Permitida"
        case .denied: "Negada"
        case .restricted: "Restrita"
        case .notDetermined: "Ainda não pedida"
        @unknown default: "Desconhecida"
        }
    }
}
