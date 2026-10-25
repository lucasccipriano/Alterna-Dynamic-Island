import SwiftUI

/// Página de um perfil. Cada ajuste pode ficar em "Não alterar".
struct ProfileEditor: View {
    @EnvironmentObject private var store: ProfileStore
    @Binding var profile: Profile

    var body: some View {
        Form {
            Section {
                HStack(spacing: 14) {
                    SymbolPicker(symbol: $profile.symbol)
                    TextField("", text: $profile.name, prompt: Text("Nome do perfil"))
                        .textFieldStyle(.plain)
                        .font(.title3.weight(.semibold))
                        .labelsHidden()
                }
                .padding(.vertical, 2)

                LabeledContent("Atalho de teclado") {
                    ShortcutRecorder(shortcut: $profile.shortcut)
                }
            }

            Section {
                Picker("Fonte de entrada", selection: $profile.inputSourceID) {
                    Text("Não alterar").tag(String?.none)
                    Divider()
                    ForEach(store.inputSources) { source in
                        Text(source.name).tag(String?.some(source.id))
                    }
                    if let id = profile.inputSourceID,
                       !store.inputSources.contains(where: { $0.id == id }) {
                        Text("Indisponível (\(id))").tag(String?.some(id))
                    }
                }
            } header: {
                Text("Teclado")
            } footer: {
                Text("A lista mostra as fontes ativadas em Ajustes do Sistema › Teclado › Fontes de Entrada.")
            }

            Section {
                Picker("Rolagem natural", selection: $profile.naturalScrolling) {
                    Text("Não alterar").tag(Bool?.none)
                    Divider()
                    Text("Ligada").tag(Bool?.some(true))
                    Text("Desligada").tag(Bool?.some(false))
                }
                Picker("Roda do mouse", selection: $profile.reverseMouseWheel) {
                    Text("Não alterar").tag(Bool?.none)
                    Divider()
                    Text("Igual ao trackpad").tag(Bool?.some(false))
                    Text("Invertida").tag(Bool?.some(true))
                }
            } header: {
                Text("Rolagem")
            } footer: {
                Text("O macOS usa a mesma direção para mouse e trackpad. \"Invertida\" troca só a roda do mouse, para você ter rolagem natural no trackpad e tradicional no mouse ao mesmo tempo. Precisa da permissão de Acessibilidade.")
            }

            SpeedSection(title: "Mouse", device: .mouse, value: $profile.mouseSpeed)
            SpeedSection(title: "Trackpad", device: .trackpad, value: $profile.trackpadSpeed)

            Section {
                HStack {
                    Button("Copiar ajustes atuais do Mac") {
                        profile = store.snapshot(profile)
                    }
                    .help("Preenche o perfil com o teclado, a rolagem e as velocidades que estão em uso agora")
                    Spacer()
                    Button("Aplicar agora") {
                        store.apply(profile)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(profile.name.isEmpty ? "Sem nome" : profile.name)
        .onAppear { store.refreshStatus() }
    }
}

private struct SpeedSection: View {
    let title: String
    let device: PointerDevice
    @Binding var value: Double?

    var body: some View {
        Section(title) {
            Toggle("Ajustar velocidade do cursor", isOn: isEnabled)
            if value != nil {
                Slider(value: speed, in: PointerSpeed.range) {
                    Text("Velocidade")
                } minimumValueLabel: {
                    Image(systemName: "tortoise.fill").foregroundStyle(.secondary)
                } maximumValueLabel: {
                    Image(systemName: "hare.fill").foregroundStyle(.secondary)
                }
            }
        }
    }

    private var isEnabled: Binding<Bool> {
        Binding(
            get: { value != nil },
            set: { value = $0 ? (value ?? PointerSpeed.current(device) ?? 1) : nil }
        )
    }

    private var speed: Binding<Double> {
        Binding(get: { value ?? 1 }, set: { value = $0 })
    }
}

/// Ícone do perfil, escolhido entre símbolos SF.
private struct SymbolPicker: View {
    @Binding var symbol: String
    @State private var isPresented = false

    private static let symbols = [
        "briefcase.fill", "gamecontroller.fill", "house.fill", "laptopcomputer",
        "desktopcomputer", "keyboard.fill", "computermouse.fill", "headphones",
        "paintbrush.pointed.fill", "music.note", "film.fill", "book.fill",
        "cup.and.saucer.fill", "moon.fill", "sun.max.fill", "airplane",
        "graduationcap.fill", "hammer.fill", "chevron.left.forwardslash.chevron.right", "person.fill",
        "star.fill", "heart.fill", "bolt.fill", "globe"
    ]

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.accentColor.gradient)
                )
        }
        .buttonStyle(.plain)
        .help("Escolher ícone")
        .accessibilityLabel("Ícone do perfil")
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(34), spacing: 6), count: 6), spacing: 6) {
                ForEach(Self.symbols, id: \.self) { name in
                    Button {
                        symbol = name
                        isPresented = false
                    } label: {
                        Image(systemName: name)
                            .font(.system(size: 15))
                            .frame(width: 34, height: 34)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(name == symbol ? Color.accentColor.opacity(0.25) : Color.clear)
                            )
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(12)
        }
    }
}
