import SwiftUI

/// Página de música: o que está tocando, playlists e busca.
struct MusicPage: View {
    enum Tab: String { case nowPlaying, playlists, search }

    @AppStorage("music.tab") private var tab: Tab = .nowPlaying

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            IslandSegmented(selection: $tab, options: [
                (.nowPlaying, "Tocando agora"),
                (.playlists, "Playlists"),
                (.search, "Buscar")
            ])

            Group {
                switch tab {
                case .nowPlaying: NowPlayingView()
                case .playlists:
                    PlaylistsView()
                        .task { await SpotifyAPI.shared.loadPlaylists() }
                case .search: MusicSearchView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }
}

// MARK: - Tocando agora

private struct NowPlayingView: View {
    @ObservedObject private var spotify = SpotifyController.shared

    var body: some View {
        if !spotify.isRunning {
            IslandEmptyState(symbol: "music.note",
                             title: "O Spotify está fechado",
                             message: "Abra o Spotify para ver e controlar o que está tocando.",
                             buttonTitle: "Abrir Spotify") { spotify.openApp() }
        } else if let error = spotify.lastError, spotify.track == nil {
            IslandEmptyState(symbol: "lock.fill",
                             title: "Permissão necessária",
                             message: error,
                             buttonTitle: "Abrir Ajustes") {
                SettingsOpener.openSystemSettings("com.apple.preference.security?Privacy_Automation")
            }
        } else if let track = spotify.track {
            HStack(alignment: .top, spacing: 16) {
                ArtworkView(image: spotify.artwork, size: 132, radius: 14)
                    .shadow(color: spotify.accent.opacity(0.35), radius: 14, y: 4)

                VStack(alignment: .leading, spacing: 0) {
                    Text(track.name)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(track.artist)
                        .font(.system(size: 13))
                        .foregroundStyle(IslandStyle.secondary)
                        .lineLimit(1)
                        .padding(.top, 2)
                    Text(track.album)
                        .font(.system(size: 11))
                        .foregroundStyle(IslandStyle.tertiary)
                        .lineLimit(1)
                        .padding(.top, 1)

                    Spacer(minLength: 8)

                    ProgressBar(duration: track.duration, accent: spotify.accent)

                    HStack(spacing: 6) {
                        RoundIconButton(symbol: "shuffle", size: 28, isOn: spotify.shuffling,
                                        help: "Aleatório") { spotify.toggleShuffle() }
                        Spacer(minLength: 0)
                        RoundIconButton(symbol: "backward.fill", size: 36, help: "Anterior") { spotify.previous() }
                        RoundIconButton(symbol: spotify.isPlaying ? "pause.fill" : "play.fill", size: 46,
                                        help: spotify.isPlaying ? "Pausar" : "Tocar") { spotify.playPause() }
                            .contentTransition(.symbolEffect(.replace))
                        RoundIconButton(symbol: "forward.fill", size: 36, help: "Próxima") { spotify.next() }
                        Spacer(minLength: 0)
                        RoundIconButton(symbol: "repeat", size: 28, isOn: spotify.repeating,
                                        help: "Repetir") { spotify.toggleRepeat() }
                    }
                    .padding(.top, 4)
                }
                .frame(maxHeight: 132)

                VolumeControl()
                    .frame(height: 132)
            }
            .frame(maxHeight: .infinity, alignment: .center)
        } else {
            IslandEmptyState(symbol: "play.circle",
                             title: "Nada tocando",
                             message: "Escolha uma playlist ou busque uma música.",
                             buttonTitle: "Ver playlists") {
                UserDefaults.standard.set(MusicPage.Tab.playlists.rawValue, forKey: "music.tab")
            }
        }
    }
}

/// Barra de progresso arrastável, como a do Centro de Controle.
private struct ProgressBar: View {
    let duration: Double
    let accent: Color
    @ObservedObject private var spotify = SpotifyController.shared
    @State private var dragValue: Double?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
            let current = dragValue ?? spotify.currentPosition(at: context.date)
            VStack(spacing: 3) {
                GeometryReader { proxy in
                    let fraction = duration > 0 ? min(max(current / duration, 0), 1) : 0
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.18))
                        Capsule().fill(.white.opacity(0.9))
                            .frame(width: proxy.size.width * fraction)
                    }
                    .frame(height: dragValue == nil ? 5 : 8)
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let x = min(max(value.location.x / proxy.size.width, 0), 1)
                            dragValue = x * duration
                        }
                        .onEnded { _ in
                            if let dragValue { spotify.seek(to: dragValue) }
                            dragValue = nil
                        })
                    .animation(.island, value: dragValue == nil)
                }
                .frame(height: 10)

                HStack {
                    Text(Self.format(current))
                    Spacer()
                    Text("-" + Self.format(max(duration - current, 0)))
                }
                .font(.system(size: 10, weight: .medium).monospacedDigit())
                .foregroundStyle(IslandStyle.tertiary)
            }
        }
    }

    static func format(_ seconds: Double) -> String {
        let s = Int(seconds.rounded(.down))
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

/// Volume vertical, ao lado do player.
private struct VolumeControl: View {
    @ObservedObject private var spotify = SpotifyController.shared
    @State private var dragValue: Double?

    var body: some View {
        let value = dragValue ?? spotify.volume
        VStack(spacing: 6) {
            Image(systemName: "speaker.wave.3.fill")
                .font(.system(size: 10))
                .foregroundStyle(IslandStyle.tertiary)
            GeometryReader { proxy in
                ZStack(alignment: .bottom) {
                    Capsule().fill(.white.opacity(0.18))
                    Capsule().fill(.white.opacity(0.9))
                        .frame(height: proxy.size.height * value / 100)
                }
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        let fraction = 1 - min(max(drag.location.y / proxy.size.height, 0), 1)
                        dragValue = fraction * 100
                        spotify.setVolume(fraction * 100)
                    }
                    .onEnded { _ in dragValue = nil })
            }
            .frame(width: 6)
            Image(systemName: "speaker.fill")
                .font(.system(size: 10))
                .foregroundStyle(IslandStyle.tertiary)
        }
        .help("Volume do Spotify")
    }
}

// MARK: - Playlists

private struct PlaylistsView: View {
    @ObservedObject private var api = SpotifyAPI.shared
    @ObservedObject private var spotify = SpotifyController.shared

    var body: some View {
        if !api.isConnected {
            ConnectSpotifyView(reason: "Conecte sua conta para ver suas playlists aqui.")
        } else if api.isLoadingPlaylists && api.playlists.isEmpty {
            ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if api.playlists.isEmpty {
            IslandEmptyState(symbol: "music.note.list", title: "Nenhuma playlist",
                             message: api.errorMessage ?? "Suas playlists aparecem aqui.",
                             buttonTitle: "Atualizar") {
                Task { await api.loadPlaylists(force: true) }
            }
        } else {
            ScrollView(.vertical, showsIndicators: false) {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 88, maximum: 110), spacing: 12)], spacing: 12) {
                    LikedSongsTile()
                    ForEach(api.playlists) { item in
                        PlaylistTile(item: item) { spotify.play(uri: item.uri) }
                    }
                }
                .padding(.bottom, 4)
            }
        }
    }
}

private struct PlaylistTile: View {
    let item: SpotifyItem
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            ZStack {
                RemoteImage(url: item.imageURL, size: 88, radius: 10)
                if hovering {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 30))
                        .foregroundStyle(.white)
                        .shadow(radius: 6)
                        .transition(.opacity)
                }
            }
            Text(item.name)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white)
                .lineLimit(2)
                .frame(width: 88, alignment: .leading)
        }
        .contentShape(Rectangle())
        .onHover { h in withAnimation(.easeOut(duration: 0.15)) { hovering = h } }
        .linkCursor()
        .onTapGesture(perform: action)
        .help("Tocar \(item.name)")
    }
}

/// "Músicas Curtidas": primeiro item da grade, com o visual de gradiente e coração.
private struct LikedSongsTile: View {
    @ObservedObject private var api = SpotifyAPI.shared
    @ObservedObject private var spotify = SpotifyController.shared
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(LinearGradient(colors: [Color(red: 0.27, green: 0.13, blue: 0.85),
                                                  Color(red: 0.55, green: 0.75, blue: 0.95)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                Image(systemName: hovering ? "play.circle.fill" : "heart.fill")
                    .font(.system(size: hovering ? 30 : 28, weight: .semibold))
                    .foregroundStyle(.white)
                    .shadow(radius: hovering ? 6 : 0)
                    .contentTransition(.symbolEffect(.replace))
            }
            .frame(width: 88, height: 88)
            VStack(alignment: .leading, spacing: 0) {
                Text("Músicas Curtidas")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                if let count = api.likedCount {
                    Text(count == 1 ? "1 música" : "\(count) músicas")
                        .font(.system(size: 10))
                        .foregroundStyle(IslandStyle.tertiary)
                }
            }
            .frame(width: 88, alignment: .leading)
        }
        .contentShape(Rectangle())
        .onHover { h in withAnimation(.easeOut(duration: 0.15)) { hovering = h } }
        .linkCursor()
        .onTapGesture { spotify.playLikedSongs() }
        .help("Tocar Músicas Curtidas")
        .task { if api.likedCount == nil { await api.loadLiked() } }
    }
}

// MARK: - Busca

private struct MusicSearchView: View {
    @ObservedObject private var api = SpotifyAPI.shared
    @ObservedObject private var spotify = SpotifyController.shared
    @State private var query = ""
    @State private var results: [SpotifyItem] = []
    @State private var searching = false
    @State private var searchTask: Task<Void, Never>?
    @State private var scope: SpotifyAPI.SearchScope = .all

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                IslandSearchField(prompt: api.isConnected ? Self.prompt(scope) : "Buscar no Spotify",
                                  text: $query) {
                    if api.isConnected { runSearch(delay: 0) } else { spotify.openSearch(query) }
                }
                if api.isConnected {
                    ScopePicker(scope: $scope)
                }
            }
            .onChange(of: query) { _, _ in
                if api.isConnected { runSearch(delay: 0.35) }
            }
            .onChange(of: scope) { _, _ in
                results = []
                if api.isConnected { runSearch(delay: 0) }
            }

            if !api.isConnected {
                Text("Aperte Enter para buscar no app do Spotify. Para ver os resultados aqui, conecte o Spotify nos Ajustes.")
                    .font(.system(size: 11))
                    .foregroundStyle(IslandStyle.tertiary)
            } else if searching && results.isEmpty {
                ProgressView().controlSize(.small).frame(maxWidth: .infinity).padding(.top, 20)
            } else if !query.isEmpty && results.isEmpty {
                Text(api.errorMessage ?? "Nada encontrado.")
                    .font(.system(size: 12))
                    .foregroundStyle(IslandStyle.secondary)
                    .padding(.top, 8)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 0) {
                        ForEach(results) { item in
                            HoverRow(action: { spotify.play(uri: item.uri) }) {
                                HStack(spacing: 10) {
                                    RemoteImage(url: item.imageURL, size: 34,
                                                radius: item.kind == .artist ? 17 : (item.kind == .show || item.kind == .episode ? 8 : 6))
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(item.name)
                                            .font(.system(size: 12, weight: .medium))
                                            .foregroundStyle(.white)
                                            .lineLimit(1)
                                        Text(item.subtitle)
                                            .font(.system(size: 11))
                                            .foregroundStyle(IslandStyle.secondary)
                                            .lineLimit(1)
                                    }
                                    Spacer()
                                    Image(systemName: Self.symbol(item.kind))
                                        .font(.system(size: 11))
                                        .foregroundStyle(IslandStyle.tertiary)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func runSearch(delay: Double) {
        searchTask?.cancel()
        let text = query
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { results = []; return }
        searchTask = Task {
            if delay > 0 { try? await Task.sleep(for: .seconds(delay)) }
            guard !Task.isCancelled else { return }
            searching = true
            let found = await api.search(text, scope: scope)
            guard !Task.isCancelled else { return }
            results = found
            searching = false
        }
    }

    private static func symbol(_ kind: SpotifyItem.Kind) -> String {
        switch kind {
        case .track: "music.note"
        case .artist: "music.mic"
        case .album: "square.stack"
        case .playlist: "music.note.list"
        case .show: "mic.fill"
        case .episode: "play.circle"
        }
    }

    private static func prompt(_ scope: SpotifyAPI.SearchScope) -> String {
        switch scope {
        case .all: "Músicas, artistas, álbuns, playlists ou podcasts"
        case .music: "Músicas, artistas, álbuns ou playlists"
        case .podcasts: "Podcasts ou episódios"
        }
    }
}

/// Filtro da busca: Tudo, Músicas ou Podcasts.
private struct ScopePicker: View {
    @Binding var scope: SpotifyAPI.SearchScope
    @Namespace private var ns

    var body: some View {
        HStack(spacing: 2) {
            ForEach(SpotifyAPI.SearchScope.allCases) { item in
                let active = item == scope
                Button {
                    withAnimation(.island) { scope = item }
                } label: {
                    Text(item.title)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(active ? Color.black : IslandStyle.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background {
                            if active {
                                Capsule().fill(.white).matchedGeometryEffect(id: "scope", in: ns)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .linkCursor(!active)
            }
        }
        .padding(2)
        .background(Capsule().fill(IslandStyle.card))
        .fixedSize()
    }
}

// MARK: - Compartilhado

struct ConnectSpotifyView: View {
    let reason: String
    @ObservedObject private var api = SpotifyAPI.shared

    var body: some View {
        VStack(spacing: 10) {
            IslandEmptyState(symbol: "person.crop.circle.badge.plus",
                             title: api.isConnecting ? "Termine o login no navegador…" : "Entre com sua conta do Spotify",
                             message: api.errorMessage ?? (api.clientID.isEmpty
                                ? "\(reason) Na primeira vez, o Spotify pede um Client ID (os Ajustes mostram como)."
                                : reason))
            SpotifyLoginButton()
                .padding(.bottom, 6)
        }
    }
}

/// Botão verde "Entrar com o Spotify", que abre o login no navegador.
struct SpotifyLoginButton: View {
    @ObservedObject private var api = SpotifyAPI.shared
    @State private var hovering = false

    var body: some View {
        Button {
            api.signIn()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: api.isConnecting ? "hourglass" : "person.crop.circle.fill")
                Text(api.isConnecting ? "Aguardando o navegador…" : "Entrar com o Spotify")
            }
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(.black)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Capsule().fill(Color(red: 0.11, green: 0.84, blue: 0.38).opacity(hovering ? 0.85 : 1)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .linkCursor()
        .help("Abre o login do Spotify no navegador")
    }
}

/// Imagem da internet com cantos arredondados.
struct RemoteImage: View {
    let url: URL?
    var size: CGFloat
    var radius: CGFloat = 8

    var body: some View {
        AsyncImage(url: url) { phase in
            if let image = phase.image {
                image.resizable().aspectRatio(contentMode: .fill)
            } else {
                ZStack {
                    IslandStyle.card
                    Image(systemName: "music.note")
                        .font(.system(size: size * 0.35))
                        .foregroundStyle(IslandStyle.tertiary)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}
