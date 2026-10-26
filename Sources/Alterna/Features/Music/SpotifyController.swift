import AppKit
import SwiftUI

/// Player do Spotify via AppleScript (o app do Spotify precisa estar instalado).
/// Não abre o Spotify sozinho: só conversa com ele se já estiver rodando.
@MainActor
final class SpotifyController: ObservableObject {
    static let shared = SpotifyController()
    static let bundleID = "com.spotify.client"

    struct Track: Equatable {
        var id: String
        var name: String
        var artist: String
        var album: String
        var artworkURL: String
        var duration: Double // segundos
    }

    @Published private(set) var isRunning = false
    @Published private(set) var isPlaying = false
    @Published private(set) var track: Track?
    @Published private(set) var position: Double = 0
    @Published private(set) var positionDate = Date()
    @Published private(set) var shuffling = false
    @Published private(set) var repeating = false
    @Published private(set) var volume: Double = 50
    @Published private(set) var artwork: NSImage?
    @Published private(set) var accent: Color = .white
    @Published private(set) var lastError: String?

    private var timer: Timer?
    private var scripts: [String: NSAppleScript] = [:]
    private var artworkTask: Task<Void, Never>?
    private var loadedArtworkURL: String?

    private init() {}

    func start() {
        // O Spotify avisa quando a faixa ou o estado mudam.
        DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.spotify.client.PlaybackStateChanged"),
            object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.refresh() }
            }

        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.refresh() }
            }
        }

        timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        refresh()
    }

    /// Posição estimada agora (entre uma leitura e outra).
    func currentPosition(at date: Date = Date()) -> Double {
        guard isPlaying else { return position }
        let value = position + date.timeIntervalSince(positionDate)
        return min(value, track?.duration ?? value)
    }

    // MARK: - Leitura

    func refresh() {
        let running = !NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleID).isEmpty
        if running != isRunning { isRunning = running }
        guard running else {
            if isPlaying { isPlaying = false }
            if track != nil { track = nil; artwork = nil; loadedArtworkURL = nil }
            return
        }

        let source = """
        tell application id "com.spotify.client"
            set s to player state as string
            if s is "stopped" then return "stopped"
            set t to current track
            set sep to "|~|"
            return s & sep & (id of t) & sep & (name of t) & sep & (artist of t) & sep & (album of t) & sep & (artwork url of t) & sep & ((duration of t) as string) & sep & ((player position) as string) & sep & (shuffling as string) & sep & (repeating as string) & sep & ((sound volume) as string)
        end tell
        """
        guard let output = run(source) else { return }
        if output == "stopped" {
            isPlaying = false
            track = nil
            return
        }

        let parts = output.components(separatedBy: "|~|")
        guard parts.count >= 11 else { return }

        let newTrack = Track(id: parts[1],
                             name: parts[2],
                             artist: parts[3],
                             album: parts[4],
                             artworkURL: parts[5],
                             duration: (Self.number(parts[6]) ?? 0) / 1000)
        let playing = parts[0] == "playing"

        if newTrack != track { track = newTrack }
        if playing != isPlaying { isPlaying = playing }
        position = Self.number(parts[7]) ?? 0
        positionDate = Date()
        shuffling = parts[8] == "true"
        repeating = parts[9] == "true"
        volume = Self.number(parts[10]) ?? volume
        loadArtwork(newTrack.artworkURL)
    }

    // MARK: - Comandos

    func playPause() {
        command("playpause")
        isPlaying.toggle()
        positionDate = Date()
    }
    func next() { command("next track") }
    func previous() { command("previous track") }

    func seek(to seconds: Double) {
        command("set player position to \(Int(seconds))")
        position = seconds
        positionDate = Date()
    }

    func setVolume(_ value: Double) {
        volume = value
        command("set sound volume to \(Int(value))")
    }

    func toggleShuffle() { command("set shuffling to \(!shuffling)"); shuffling.toggle() }
    func toggleRepeat() { command("set repeating to \(!repeating)"); repeating.toggle() }

    /// Toca uma faixa, playlist, álbum ou artista pelo URI (spotify:track:…).
    func play(uri: String, inContext context: String? = nil) {
        if !isRunning {
            // Abre o Spotify e toca pelo próprio link.
            NSWorkspace.shared.open(URL(string: uri) ?? URL(string: "spotify:")!)
            return
        }
        if let context {
            command("play track \"\(uri)\" in context \"\(context)\"")
        } else {
            command("play track \"\(uri)\"")
        }
    }

    /// Toca as Músicas Curtidas (Liked Songs) a partir da primeira faixa.
    func playLikedSongs() {
        let api = SpotifyAPI.shared
        guard let collection = api.likedCollectionURI else {
            // Sem login na Web API: abre a coleção no próprio Spotify.
            NSWorkspace.shared.open(URL(string: "spotify:collection:tracks")!)
            return
        }
        if !isRunning {
            NSWorkspace.shared.open(URL(string: "spotify:collection:tracks")!)
            return
        }
        if let first = api.firstLikedURI {
            play(uri: first, inContext: collection)
        } else {
            play(uri: collection)
        }
    }

    func openApp() {
        AppInfo.open(Self.bundleID)
    }

    /// Busca no próprio Spotify (quando a Web API não está conectada).
    func openSearch(_ query: String) {
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? query
        if let url = URL(string: "spotify:search:\(encoded)") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Privado

    private func command(_ body: String) {
        guard isRunning else { return }
        _ = run("tell application id \"com.spotify.client\" to \(body)")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in self?.refresh() }
    }

    private func run(_ source: String) -> String? {
        let script: NSAppleScript
        if let cached = scripts[source] {
            script = cached
        } else {
            guard let created = NSAppleScript(source: source) else { return nil }
            scripts[source] = created
            script = created
        }
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        if let error {
            let number = error[NSAppleScript.errorNumber] as? Int ?? 0
            lastError = number == -1743
                ? "Permita que o Alterna controle o Spotify em Ajustes do Sistema › Privacidade e Segurança › Automação."
                : (error[NSAppleScript.errorMessage] as? String)
            return nil
        }
        lastError = nil
        return result.stringValue
    }

    private static func number(_ text: String) -> Double? {
        Double(text.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces))
    }

    private func loadArtwork(_ urlString: String) {
        guard urlString != loadedArtworkURL, let url = URL(string: urlString) else { return }
        loadedArtworkURL = urlString
        artworkTask?.cancel()
        artworkTask = Task { [weak self] in
            guard let result = try? await URLSession.shared.data(from: url),
                  let image = NSImage(data: result.0),
                  !Task.isCancelled else { return }
            let color = image.averageColor
            await MainActor.run {
                guard let self else { return }
                self.artwork = image
                self.accent = color.map { Color(nsColor: $0) } ?? .white
            }
        }
    }
}

// MARK: - Cor média da capa

extension NSImage {
    /// Cor média, clareada para ficar visível sobre o preto.
    var averageColor: NSColor? {
        guard let cg = cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        var pixel = [UInt8](repeating: 0, count: 4)
        guard let context = CGContext(data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.interpolationQuality = .medium
        context.draw(cg, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        let color = NSColor(red: CGFloat(pixel[0]) / 255, green: CGFloat(pixel[1]) / 255,
                            blue: CGFloat(pixel[2]) / 255, alpha: 1)
        guard let hsb = color.usingColorSpace(.deviceRGB) else { return color }
        return NSColor(hue: hsb.hueComponent,
                       saturation: min(hsb.saturationComponent * 1.2, 1),
                       brightness: max(hsb.brightnessComponent, 0.75),
                       alpha: 1)
    }
}
