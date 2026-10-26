import AppKit
import CryptoKit
import Foundation
import Network
import Security

/// Resultado de playlist ou busca no Spotify.
struct SpotifyItem: Identifiable, Hashable {
    enum Kind: String { case track, playlist, album, artist }
    var id: String { uri }
    let uri: String
    let name: String
    let subtitle: String
    let imageURL: URL?
    let kind: Kind
}

/// Web API do Spotify (playlists e busca), com login PKCE.
/// Exige um app de desenvolvedor em developer.spotify.com com o
/// Redirect URI http://127.0.0.1:43821/callback
@MainActor
final class SpotifyAPI: ObservableObject {
    static let shared = SpotifyAPI()
    static let port: UInt16 = 43821
    static let redirectURI = "http://127.0.0.1:43821/callback"
    private static let scopes = "playlist-read-private playlist-read-collaborative user-read-private user-library-read"

    @Published var clientID: String {
        didSet { UserDefaults.standard.set(clientID.trimmingCharacters(in: .whitespaces), forKey: "spotify.clientID") }
    }
    @Published private(set) var isConnected = false
    @Published private(set) var isConnecting = false
    @Published private(set) var userName: String?
    @Published private(set) var playlists: [SpotifyItem] = []
    /// Músicas Curtidas (Liked Songs): total e a primeira faixa (para tocar a coleção).
    @Published private(set) var likedCount: Int?
    private(set) var firstLikedURI: String?
    private(set) var userID: String?
    @Published private(set) var isLoadingPlaylists = false
    @Published private(set) var errorMessage: String?

    private struct Token: Codable {
        var access: String
        var refresh: String
        var expiry: Date
    }

    private var token: Token? {
        didSet {
            if let token, let data = try? JSONEncoder().encode(token) {
                Keychain.save(data)
            } else {
                Keychain.delete()
            }
            isConnected = token != nil
        }
    }

    private var listener: NWListener?
    private var verifier = ""
    private var state = ""

    private init() {
        clientID = UserDefaults.standard.string(forKey: "spotify.clientID") ?? ""
        if let data = Keychain.load(), let saved = try? JSONDecoder().decode(Token.self, from: data) {
            token = saved
            isConnected = true
        }
    }

    // MARK: - Login

    func connect() {
        errorMessage = nil
        guard !clientID.isEmpty else {
            errorMessage = "Cole o Client ID do seu app do Spotify nos Ajustes do Alterna › Música."
            return
        }
        verifier = Self.randomString(64)
        state = Self.randomString(16)
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64URLEncoded

        guard startListener() else { return }

        var components = URLComponents(string: "https://accounts.spotify.com/authorize")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: Self.redirectURI),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "scope", value: Self.scopes),
            URLQueryItem(name: "state", value: state)
        ]
        isConnecting = true
        NSWorkspace.shared.open(components.url!)
    }

    /// Botão "Entrar com o Spotify": abre o login do Spotify no navegador.
    /// Sem Client ID, abre o painel de desenvolvedor (login com a conta do Spotify)
    /// e os Ajustes para colar o Client ID.
    func signIn() {
        if clientID.isEmpty {
            NSWorkspace.shared.open(URL(string: "https://developer.spotify.com/dashboard")!)
            IslandController.shared.collapse()
            SettingsWindowController.shared.show(pane: "music")
            errorMessage = nil
        } else {
            connect()
        }
    }

    func disconnect() {
        token = nil
        playlists = []
        userName = nil
    }

    // MARK: - Playlists e busca

    func loadPlaylists(force: Bool = false) async {
        guard isConnected, force || playlists.isEmpty, !isLoadingPlaylists else { return }
        isLoadingPlaylists = true
        defer { isLoadingPlaylists = false }
        do {
            let page = try await get("/me/playlists", query: [URLQueryItem(name: "limit", value: "50")],
                                     as: Page<APIPlaylist>.self)
            playlists = page.items.compactMap { $0?.item }
            errorMessage = nil
            await loadLiked()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Músicas Curtidas: quantas são e qual é a primeira.
    func loadLiked() async {
        guard isConnected else { return }
        if userID == nil { await loadProfile() }
        if let page = try? await get("/me/tracks", query: [URLQueryItem(name: "limit", value: "1")],
                                     as: LikedPage.self) {
            likedCount = page.total
            firstLikedURI = page.items.first??.track?.uri
        }
    }

    /// Endereço da coleção "Músicas Curtidas" no Spotify.
    var likedCollectionURI: String? {
        userID.map { "spotify:user:\($0):collection" }
    }

    func search(_ text: String) async -> [SpotifyItem] {
        let q = text.trimmingCharacters(in: .whitespaces)
        guard isConnected, !q.isEmpty else { return [] }
        do {
            let result = try await get("/search", query: [
                URLQueryItem(name: "q", value: q),
                URLQueryItem(name: "type", value: "track,artist,album,playlist"),
                URLQueryItem(name: "limit", value: "6")
            ], as: SearchResponse.self)
            errorMessage = nil
            var items: [SpotifyItem] = []
            items += (result.tracks?.items ?? []).compactMap { $0?.item }
            items += (result.artists?.items ?? []).compactMap { $0?.item }.prefix(3)
            items += (result.albums?.items ?? []).compactMap { $0?.item }.prefix(4)
            items += (result.playlists?.items ?? []).compactMap { $0?.item }.prefix(4)
            return items
        } catch {
            errorMessage = error.localizedDescription
            return []
        }
    }

    func loadProfile() async {
        guard isConnected else { return }
        if let me = try? await get("/me", as: Me.self) {
            userName = me.display_name
            userID = me.id
        }
    }

    // MARK: - HTTP

    private enum APIError: LocalizedError {
        case notConnected, forbidden, http(Int)
        var errorDescription: String? {
            switch self {
            case .notConnected: "Conecte sua conta do Spotify."
            case .forbidden: "O Spotify recusou o acesso. A conta dona do app precisa ser Premium e o seu e-mail precisa estar na lista de usuários do app (User Management)."
            case .http(let code): "O Spotify respondeu com erro \(code)."
            }
        }
    }

    private func get<T: Decodable>(_ path: String, query: [URLQueryItem] = [], as type: T.Type,
                                   retry: Bool = true) async throws -> T {
        let access = try await validAccessToken()
        var components = URLComponents(string: "https://api.spotify.com/v1" + path)!
        if !query.isEmpty { components.queryItems = query }
        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(access)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 401, retry {
            token?.expiry = .distantPast
            return try await get(path, query: query, as: type, retry: false)
        }
        if status == 403 { throw APIError.forbidden }
        guard (200..<300).contains(status) else { throw APIError.http(status) }
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func validAccessToken() async throws -> String {
        guard let current = token else { throw APIError.notConnected }
        if current.expiry > Date().addingTimeInterval(60) { return current.access }
        let response = try await tokenRequest([
            "grant_type": "refresh_token",
            "refresh_token": current.refresh,
            "client_id": clientID
        ])
        token = Token(access: response.access_token,
                      refresh: response.refresh_token ?? current.refresh,
                      expiry: Date().addingTimeInterval(TimeInterval(response.expires_in)))
        return response.access_token
    }

    private func exchange(code: String) async {
        do {
            let response = try await tokenRequest([
                "grant_type": "authorization_code",
                "code": code,
                "redirect_uri": Self.redirectURI,
                "client_id": clientID,
                "code_verifier": verifier
            ])
            token = Token(access: response.access_token,
                          refresh: response.refresh_token ?? "",
                          expiry: Date().addingTimeInterval(TimeInterval(response.expires_in)))
            errorMessage = nil
            await loadProfile()
            await loadPlaylists(force: true)
        } catch {
            errorMessage = "Não foi possível entrar no Spotify: \(error.localizedDescription)"
        }
        isConnecting = false
    }

    private func tokenRequest(_ fields: [String: String]) async throws -> TokenResponse {
        var request = URLRequest(url: URL(string: "https://accounts.spotify.com/api/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        request.httpBody = fields
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: allowed) ?? $0.value)" }
            .joined(separator: "&")
            .data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            if status == 400 || status == 401 { token = nil }
            throw APIError.http(status)
        }
        return try JSONDecoder().decode(TokenResponse.self, from: data)
    }

    // MARK: - Servidor local do retorno do login

    private func startListener() -> Bool {
        listener?.cancel()
        do {
            let parameters = NWParameters.tcp
            parameters.requiredInterfaceType = .loopback
            parameters.allowLocalEndpointReuse = true
            let listener = try NWListener(using: parameters, on: NWEndpoint.Port(rawValue: Self.port)!)
            listener.newConnectionHandler = { [weak self] connection in
                connection.start(queue: .main)
                connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { data, _, _, _ in
                    MainActor.assumeIsolated {
                        self?.handleCallback(data: data, connection: connection)
                    }
                }
            }
            listener.start(queue: .main)
            self.listener = listener
            return true
        } catch {
            errorMessage = "Não foi possível abrir a porta \(Self.port) para o login: \(error.localizedDescription)"
            return false
        }
    }

    private func handleCallback(data: Data?, connection: NWConnection) {
        let request = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
        let path = request.split(separator: " ").dropFirst().first.map(String.init) ?? ""
        guard path.hasPrefix("/callback") else {
            respond(connection, status: "404 Not Found", body: "")
            return
        }

        let items = URLComponents(string: "http://127.0.0.1" + path)?.queryItems ?? []
        let code = items.first { $0.name == "code" }?.value
        let returnedState = items.first { $0.name == "state" }?.value
        let failure = items.first { $0.name == "error" }?.value

        let ok = code != nil && returnedState == state && failure == nil
        respond(connection, status: "200 OK", body: Self.page(success: ok))

        listener?.cancel()
        listener = nil

        if ok, let code {
            Task { await exchange(code: code) }
        } else {
            isConnecting = false
            errorMessage = failure == "access_denied" ? "Login cancelado." : "O login do Spotify falhou."
        }
    }

    private func respond(_ connection: NWConnection, status: String, body: String) {
        let response = "HTTP/1.1 \(status)\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
        connection.send(content: response.data(using: .utf8), completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private static func page(success: Bool) -> String {
        let title = success ? "Spotify conectado" : "Não deu certo"
        let message = success ? "Pode fechar esta aba e voltar para o Alterna." : "Volte ao Alterna e tente conectar de novo."
        return """
        <!doctype html><html lang="pt-BR"><meta charset="utf-8"><title>Alterna</title>
        <body style="margin:0;height:100vh;display:grid;place-items:center;background:#000;color:#fff;font:15px -apple-system,system-ui">
        <div style="text-align:center"><div style="font-size:44px">\(success ? "✓" : "✕")</div>
        <h1 style="font-size:22px;margin:12px 0 6px">\(title)</h1><p style="color:#aaa">\(message)</p></div></body></html>
        """
    }

    private static func randomString(_ length: Int) -> String {
        let chars = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return String((0..<length).map { _ in chars.randomElement()! })
    }
}

// MARK: - Modelos da API

private struct TokenResponse: Decodable {
    let access_token: String
    let expires_in: Int
    let refresh_token: String?
}

private struct Me: Decodable {
    let id: String?
    let display_name: String?
}

private struct LikedPage: Decodable {
    struct Item: Decodable { let track: APITrack? }
    let total: Int
    let items: [Item?]
}

private struct APIImage: Decodable { let url: String }

private struct Page<T: Decodable>: Decodable {
    let items: [T?]
}

private struct APIOwner: Decodable { let display_name: String? }

private struct APIArtist: Decodable {
    let name: String
    let uri: String?
    let images: [APIImage]?

    var item: SpotifyItem? {
        guard let uri else { return nil }
        return SpotifyItem(uri: uri, name: name, subtitle: "Artista",
                           imageURL: images?.first.flatMap { URL(string: $0.url) }, kind: .artist)
    }
}

private struct APIAlbum: Decodable {
    let name: String
    let uri: String?
    let images: [APIImage]?
    let artists: [APIArtist]?

    var item: SpotifyItem? {
        guard let uri else { return nil }
        let by = artists?.map(\.name).joined(separator: ", ") ?? ""
        return SpotifyItem(uri: uri, name: name, subtitle: by.isEmpty ? "Álbum" : "Álbum · \(by)",
                           imageURL: images?.first.flatMap { URL(string: $0.url) }, kind: .album)
    }
}

private struct APITrack: Decodable {
    let name: String
    let uri: String
    let artists: [APIArtist]
    let album: APIAlbum?

    var item: SpotifyItem? {
        SpotifyItem(uri: uri, name: name, subtitle: artists.map(\.name).joined(separator: ", "),
                    imageURL: album?.images?.last.flatMap { URL(string: $0.url) }, kind: .track)
    }
}

private struct APIPlaylist: Decodable {
    let name: String
    let uri: String
    let images: [APIImage]?
    let owner: APIOwner?

    var item: SpotifyItem? {
        SpotifyItem(uri: uri, name: name, subtitle: owner?.display_name ?? "Playlist",
                    imageURL: images?.first.flatMap { URL(string: $0.url) }, kind: .playlist)
    }
}

private struct SearchResponse: Decodable {
    let tracks: Page<APITrack>?
    let artists: Page<APIArtist>?
    let albums: Page<APIAlbum>?
    let playlists: Page<APIPlaylist>?
}

// MARK: - Utilidades

private extension Data {
    var base64URLEncoded: String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

/// Guarda o login do Spotify nas Chaves (Keychain).
enum Keychain {
    private static let service = "app.alterna.spotify"
    private static let account = "token"

    private static var base: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    static func save(_ data: Data) {
        delete()
        var query = base
        query[kSecValueData as String] = data
        SecItemAdd(query as CFDictionary, nil)
    }

    static func load() -> Data? {
        var query = base
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }

    static func delete() {
        SecItemDelete(base as CFDictionary)
    }
}
