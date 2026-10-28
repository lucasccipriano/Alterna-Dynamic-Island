import SwiftUI

/// Página "Alternar": perfis de teclado, rolagem e velocidade, mais atalhos rápidos.
struct ProfilesPage: View {
    @ObservedObject private var store = ProfileStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if store.profiles.isEmpty {
                IslandEmptyState(symbol: "switch.2", title: "Nenhum perfil",
                                 message: "Crie perfis como Trabalho e Lazer. O perfil novo começa com os ajustes atuais do Mac.",
                                 buttonTitle: "Criar perfil") { NewProfileCard.create() }
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(store.profiles) { profile in
                            ProfileCard(profile: profile, isActive: profile.id == store.activeProfileID) {
                                store.apply(profile)
                            }
                        }
                        NewProfileCard()
                    }
                }
                .scrollDisabled(store.profiles.count <= 3)

                QuickControls()
            }
        }
        .onAppear { store.refreshStatus() }
    }
}

private struct ProfileCard: View {
    let profile: Profile
    let isActive: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: profile.symbol)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(isActive ? Color.white : .white.opacity(0.9))
                        .frame(width: 34, height: 34)
                        .background(Circle().fill(isActive ? Color.accentColor : .white.opacity(0.12)))
                    Spacer()
                    if isActive {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Color.accentColor)
                    }
                }
                Text(profile.name.isEmpty ? "Sem nome" : profile.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(profile.summary)
                    .font(.system(size: 10))
                    .foregroundStyle(IslandStyle.secondary)
                    .lineLimit(2, reservesSpace: true)
                Text(profile.shortcut?.display ?? " ")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(IslandStyle.tertiary)
            }
            .padding(12)
            .frame(width: 132, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(hovering ? IslandStyle.cardHover : IslandStyle.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(isActive ? Color.accentColor.opacity(0.7) : .clear, lineWidth: 1.5)
            )
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .linkCursor()
        .help("Aplicar \(profile.name)")
    }
}

/// Ajustes avulsos, sem precisar de perfil.
private struct QuickControls: View {
    @ObservedObject private var store = ProfileStore.shared
    @State private var natural = ScrollDirection.isNatural

    var body: some View {
        HStack(spacing: 10) {
            Menu {
                ForEach(store.inputSources) { source in
                    Button {
                        InputSources.select(id: source.id)
                        store.refreshStatus()
                    } label: {
                        if source.id == store.currentInputSource?.id {
                            Label(source.name, systemImage: "checkmark")
                        } else {
                            Text(source.name)
                        }
                    }
                }
            } label: {
                Label(store.currentInputSource?.name ?? "Teclado", systemImage: "keyboard")
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.visible)
            .fixedSize()
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(Capsule().fill(IslandStyle.card))

            Toggle(isOn: Binding(get: { natural }, set: {
                natural = $0
                ScrollDirection.setNatural($0)
            })) {
                Text("Rolagem natural").font(.system(size: 12, weight: .medium)).foregroundStyle(.white)
            }
            .toggleStyle(.switch)
            .controlSize(.mini)
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(Capsule().fill(IslandStyle.card))

            Toggle(isOn: Binding(get: { store.reverseMouseWheel }, set: { store.setReverseMouseWheel($0) })) {
                Text("Inverter mouse").font(.system(size: 12, weight: .medium)).foregroundStyle(.white)
            }
            .toggleStyle(.switch)
            .controlSize(.mini)
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(Capsule().fill(IslandStyle.card))
            .help("Inverte só a roda do mouse, sem mexer no trackpad")

            Spacer(minLength: 0)
        }
    }
}

/// Estado da página quando os perfis estão desligados nos Ajustes:
/// explica o que a função faz e oferece um switch para ligar ali mesmo.
struct ProfilesDisabledView: View {
    @ObservedObject private var store = ProfileStore.shared

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "keyboard")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(IslandStyle.secondary)
            Text("Perfis de teclado desligados")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
            Text("Ligue para trocar idioma do teclado, rolagem e velocidade do mouse com um clique ou atalho.")
                .font(.system(size: 12))
                .foregroundStyle(IslandStyle.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
            Toggle(isOn: Binding(get: { store.profilesEnabled },
                                 set: { on in withAnimation(.island) { store.profilesEnabled = on } })) {
                Text("Perfis de teclado")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white)
            }
            .toggleStyle(.switch)
            .controlSize(.small)
            .padding(.horizontal, 12).padding(.vertical, 5)
            .background(Capsule().fill(IslandStyle.card))
            .fixedSize()
            .linkCursor()
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Cartão "+ Novo perfil": cria um perfil com os ajustes atuais do Mac
/// e abre o editor nos Ajustes para dar nome, ícone e atalho.
struct NewProfileCard: View {
    @State private var hovering = false

    @MainActor
    static func create() {
        let store = ProfileStore.shared
        var profile = store.addProfile()
        profile.name = nextName(store.profiles.map(\.name))
        if let index = store.profiles.firstIndex(where: { $0.id == profile.id }) {
            store.profiles[index] = profile
        }
        IslandController.shared.collapse()
        SettingsWindowController.shared.show(pane: "profile:\(profile.id.uuidString)")
    }

    private static func nextName(_ existing: [String]) -> String {
        var n = 1
        while existing.contains("Perfil \(n)") { n += 1 }
        return "Perfil \(n)"
    }

    var body: some View {
        Button {
            Self.create()
        } label: {
            VStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(Color.white.opacity(hovering ? 0.2 : 0.12)))
                Text("Novo perfil")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                Text("Com os ajustes atuais do Mac")
                    .font(.system(size: 10))
                    .foregroundStyle(IslandStyle.tertiary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .padding(12)
            .frame(width: 112, height: 128)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.white.opacity(hovering ? 0.35 : 0.18), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
            )
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .linkCursor()
        .help("Criar um perfil novo")
    }
}
