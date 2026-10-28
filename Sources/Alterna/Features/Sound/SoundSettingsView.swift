import SwiftUI

/// Ajustes › Som: saída do Mac e os ajustes salvos de cada app.
struct SoundSettingsView: View {
    @ObservedObject private var mixer = SoundMixer.shared

    var body: some View {
        Form {
            FeatureSection(feature: .sound)
            Section {
                Picker("Saída", selection: Binding(
                    get: { mixer.defaultOutput?.uid ?? "" },
                    set: { uid in if let d = mixer.outputs.first(where: { $0.uid == uid }) { mixer.setDefaultOutput(d) } })) {
                    ForEach(mixer.outputs) { device in
                        Label(device.name, systemImage: device.symbol).tag(device.uid)
                    }
                }
                LabeledContent("Volume geral") {
                    HStack {
                        Slider(value: Binding(get: { Double(mixer.masterVolume) },
                                              set: { mixer.setMasterVolume(Float($0)) }), in: 0...1)
                            .frame(width: 200)
                            .disabled(!mixer.canChangeMaster)
                        Toggle("Mudo", isOn: Binding(get: { mixer.masterMuted }, set: { mixer.setMasterMuted($0) }))
                    }
                }
            } header: {
                Text("Mac")
            }

            Section {
                if mixer.rules.isEmpty {
                    Text("Nenhum ajuste por app ainda. Abra a seção Som da ilha enquanto um app toca áudio e mude o volume, silencie ou escolha outra saída — o Alterna lembra e aplica sozinho da próxima vez.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(mixer.rules.keys.sorted(), id: \.self) { key in
                        let rule = mixer.rules[key] ?? AppSoundRule()
                        LabeledContent {
                            Button("Restaurar") { mixer.reset(key: key) }
                        } label: {
                            Text(displayName(key))
                            Text(describe(rule))
                        }
                    }
                    Button("Restaurar todos", role: .destructive) { mixer.resetAll() }
                }
            } header: {
                Text("Ajustes por app")
            } footer: {
                Text("Cada app pode ter volume, mudo e saída próprios (ex.: música nos fones e chamada nos alto-falantes). Funciona no macOS 14.2 ou mais novo.")
            }

            Section {
                LabeledContent {
                    Button("Abrir…") { mixer.openPrivacySettings() }
                } label: {
                    Text("Gravação de áudio do sistema")
                    Text("Necessária para ajustar o som de cada app. Fica em Privacidade e Segurança › Gravação de Tela e Áudio do Sistema.")
                }
            } header: {
                Text("Permissão")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Som")
        .onAppear { mixer.refresh() }
    }

    private func displayName(_ key: String) -> String {
        if let app = mixer.apps.first(where: { $0.id == key }) { return app.name }
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: key) {
            return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
        }
        return key
    }

    private func describe(_ rule: AppSoundRule) -> String {
        var parts = [rule.muted ? "Silenciado" : "Volume \(Int((rule.volume * 100).rounded()))%"]
        if let uid = rule.outputUID {
            parts.append("Saída: " + (mixer.outputs.first { $0.uid == uid }?.name ?? "desconectada"))
        }
        return parts.joined(separator: " · ")
    }
}
