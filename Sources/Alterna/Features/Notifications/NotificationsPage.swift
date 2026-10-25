import SwiftUI

/// Página de notificações com filtros por tipo.
struct NotificationsPage: View {
    @ObservedObject private var monitor = NotificationMonitor.shared

    var body: some View {
        if !monitor.databaseFound {
            IslandEmptyState(symbol: "bell.slash",
                             title: "Central de Notificações não encontrada",
                             message: "Esta versão do macOS guarda as notificações num lugar diferente. Avise para eu ajustar o Alterna.")
        } else if !monitor.hasAccess {
            VStack(spacing: 10) {
                IslandEmptyState(symbol: "lock.shield",
                                 title: "Dê Acesso Total ao Disco",
                                 message: "Para mostrar suas notificações, ative o Alterna em Ajustes do Sistema › Privacidade e Segurança › Acesso Total ao Disco.")
                HStack(spacing: 8) {
                    CapsuleButton(title: "Abrir Ajustes", prominent: true) {
                        SettingsOpener.openSystemSettings("com.apple.preference.security?Privacy_AllFiles")
                    }
                    CapsuleButton(title: "Já permiti") { monitor.retry() }
                }
                .padding(.bottom, 8)
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                header
                if monitor.visibleItems.isEmpty {
                    IslandEmptyState(symbol: "bell",
                                     title: "Tudo em dia",
                                     message: monitor.disabledCategories.isEmpty && monitor.disabledApps.isEmpty
                                        ? "As notificações novas aparecem aqui."
                                        : "As notificações novas aparecem aqui. Alguns tipos estão desligados nos filtros.")
                } else {
                    ScrollView(.vertical, showsIndicators: false) {
                        LazyVStack(spacing: 6) {
                            ForEach(monitor.visibleItems) { item in
                                NotificationRow(item: item)
                            }
                        }
                    }
                }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            let count = monitor.visibleItems.count
            Text(count == 1 ? "1 notificação" : "\(count) notificações")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(IslandStyle.secondary)
            Spacer()

            Menu {
                Section("Mostrar") {
                    ForEach(NotificationCategory.allCases) { category in
                        Toggle(isOn: Binding(
                            get: { !monitor.disabledCategories.contains(category) },
                            set: { monitor.setCategory(category, enabled: $0) })) {
                            Label(category.title, systemImage: category.symbol)
                        }
                    }
                }
                Divider()
                Toggle("Banner na ilha", isOn: $monitor.showBanners)
                Button("Filtrar por app…") { SettingsOpener.open() }
            } label: {
                Label("Filtros", systemImage: "line.3.horizontal.decrease.circle")
                    .font(.system(size: 12, weight: .semibold))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .foregroundStyle(.white)
            .linkCursor()

            if !monitor.visibleItems.isEmpty {
                CapsuleButton(title: "Limpar") {
                    withAnimation(.island) { monitor.clearAll() }
                }
            }
        }
    }
}

private struct NotificationRow: View {
    let item: NotificationItem
    @ObservedObject private var monitor = NotificationMonitor.shared
    @State private var hovering = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            AppIconView(bundleID: item.bundleID, size: 30)
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(item.appName)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(IslandStyle.tertiary)
                    Spacer()
                    if hovering {
                        // O X fica dentro do cartão, no lugar da hora, para nunca ser cortado.
                        Button {
                            withAnimation(.island) { _ = monitor.hiddenIDs.insert(item.id) }
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.white.opacity(0.85))
                                .frame(width: 18, height: 18)
                                .background(Circle().fill(.white.opacity(0.18)))
                                .contentShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .linkCursor()
                        .help("Dispensar")
                        .transition(.opacity.combined(with: .scale(scale: 0.6)))
                    } else {
                        Text(Self.relative(item.date))
                            .font(.system(size: 11))
                            .foregroundStyle(IslandStyle.tertiary)
                            .transition(.opacity)
                    }
                }
                .frame(height: 18)
                if !item.title.isEmpty {
                    Text(item.title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }
                let text = [item.subtitle, item.body].filter { !$0.isEmpty }.joined(separator: " — ")
                if !text.isEmpty {
                    Text(text)
                        .font(.system(size: 12))
                        .foregroundStyle(IslandStyle.secondary)
                        .lineLimit(2)
                }
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(hovering ? IslandStyle.cardHover : IslandStyle.card))
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onHover { h in withAnimation(.easeOut(duration: 0.15)) { hovering = h } }
        .linkCursor()
        .onTapGesture { monitor.open(item) }
        .contextMenu {
            Button("Abrir \(item.appName)") { monitor.open(item) }
            Button("Silenciar \(item.appName) na ilha") { monitor.setApp(item.bundleID, enabled: false) }
            Button("Silenciar \(item.category.title)") { monitor.setCategory(item.category, enabled: false) }
        }
    }

    private static let formatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    static func relative(_ date: Date) -> String {
        if Date().timeIntervalSince(date) < 60 { return "agora" }
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
