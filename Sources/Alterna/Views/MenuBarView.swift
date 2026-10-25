import SwiftUI

/// Painel da barra de menus, no estilo da Central de Controle.
struct MenuBarView: View {
    @EnvironmentObject private var store: ProfileStore
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Perfis")
                    .font(.headline)
                Spacer()
                if let source = store.currentInputSource {
                    Label(source.name, systemImage: "keyboard")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 4)

            if store.profiles.isEmpty {
                Text("Nenhum perfil ainda. Crie um nos Ajustes.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
            } else {
                VStack(spacing: 2) {
                    ForEach(store.profiles) { profile in
                        ProfileRow(profile: profile,
                                   isActive: profile.id == store.activeProfileID) {
                            store.apply(profile)
                        }
                    }
                }
            }

            Divider()

            Toggle(isOn: $settings.showIsland) {
                Label("Dynamic Island", systemImage: "capsule.fill")
            }
            .toggleStyle(.switch)
            .controlSize(.small)
            .padding(.horizontal, 6)

            Divider()

            VStack(spacing: 2) {
                MenuRow(title: "Ajustes do Alterna…", systemImage: "gearshape") {
                    openSettingsWindow()
                }
                MenuRow(title: "Sair", systemImage: "power") {
                    NSApp.terminate(nil)
                }
            }
        }
        .padding(10)
        .frame(width: 300)
        .onAppear { store.refreshStatus() }
    }

    private func openSettingsWindow() {
        SettingsOpener.open()
    }
}

private struct ProfileRow: View {
    let profile: Profile
    let isActive: Bool
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: profile.symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isActive ? Color.white : Color.primary)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(isActive ? Color.accentColor : Color.primary.opacity(0.1)))

                VStack(alignment: .leading, spacing: 1) {
                    Text(profile.name.isEmpty ? "Sem nome" : profile.name)
                        .fontWeight(.medium)
                    Text(profile.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                if let shortcut = profile.shortcut {
                    Text(shortcut.display)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isHovering ? Color.primary.opacity(0.08) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .accessibilityLabel("\(profile.name), \(isActive ? "ativo" : "inativo")")
    }
}

private struct MenuRow: View {
    let title: String
    let systemImage: String
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .frame(width: 16)
                    .foregroundStyle(.secondary)
                Text(title)
                Spacer()
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isHovering ? Color.primary.opacity(0.08) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}
