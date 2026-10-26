import AppKit

// MARK: - Resultado

struct SearchItem: Identifiable {
    let url: URL
    let name: String
    let kind: String
    var id: String { url.path }
}

enum CommandResult {
    case opened(name: String, url: URL?, detail: String)
    case items(title: String, items: [SearchItem], webQuery: String?)
    case info(symbol: String, title: String, value: String, detail: String?)
    case message(symbol: String, title: String, detail: String, webQuery: String?)
    case music(title: String, detail: String)
}

// MARK: - Motor de comandos

/// Entende comandos simples em português (e alguns em inglês):
///   "abrir Safari", "abra a pasta Downloads", "abrir contrato.pdf"
///   "pesquisar relatório", "procurar fotos da viagem"
///   "pesquisar na internet clima em Lisboa"
///   "tocar Coldplay", "pausar", "próxima música"
///   "bateria", "armazenamento", "memória", "versão do macOS", "que horas são"
@MainActor
enum CommandEngine {
    private enum Verb { case open, search, play, pause, next, previous }

    private static let verbs: [String: Verb] = [
        "abrir": .open, "abra": .open, "abre": .open, "abri": .open, "inicie": .open, "iniciar": .open,
        "inicia": .open, "execute": .open, "executar": .open, "lance": .open, "lancar": .open,
        "mostre": .open, "mostrar": .open, "mostra": .open, "open": .open, "launch": .open,
        "pesquisar": .search, "pesquise": .search, "pesquisa": .search, "procurar": .search,
        "procure": .search, "procura": .search, "buscar": .search, "busque": .search, "busca": .search,
        "encontrar": .search, "encontre": .search, "encontra": .search, "achar": .search, "ache": .search,
        "acha": .search, "search": .search, "find": .search, "localizar": .search, "localize": .search,
        "tocar": .play, "toca": .play, "toque": .play, "reproduzir": .play, "reproduza": .play,
        "coloca": .play, "coloque": .play, "colocar": .play, "play": .play, "ouvir": .play, "bota": .play,
        "pausar": .pause, "pausa": .pause, "pause": .pause, "parar": .pause, "pare": .pause, "stop": .pause,
        "pular": .next, "pula": .next, "proxima": .next, "avancar": .next, "next": .next, "skip": .next,
        "anterior": .previous, "voltar": .previous, "previous": .previous
    ]

    private static let leadingFillers: Set<String> = [
        "siri", "alterna", "ei", "hey", "ola", "oi", "por", "favor", "voce", "pode", "podes", "poderia",
        "consegue", "quero", "queria", "gostaria", "de", "me", "eu"
    ]

    private static let targetFillers: Set<String> = [
        "o", "a", "os", "as", "um", "uma", "por", "sobre", "pelo", "pela", "meu", "minha", "meus", "minhas",
        "app", "aplicativo", "aplicacao", "programa", "musica", "a musica", "no", "na", "do", "da"
    ]

    private static let webPhrases: [[String]] = [
        ["na", "internet"], ["no", "google"], ["na", "web"], ["no", "navegador"], ["online"], ["on", "line"],
        ["on", "the", "web"], ["online"]
    ]

    static func execute(_ text: String) async -> CommandResult {
        var words = text.split(whereSeparator: \.isWhitespace).map(String.init)
        var folded = words.map(fold)

        // "por favor" no fim
        while let last = folded.last, ["favor", "por", "obrigado", "obrigada"].contains(last) {
            words.removeLast(); folded.removeLast()
        }

        // Tira "siri", "você pode", "por favor"… do começo.
        while let first = folded.first, leadingFillers.contains(first), verbs[first] == nil {
            words.removeFirst(); folded.removeFirst()
        }
        guard !folded.isEmpty else {
            return .message(symbol: "questionmark.bubble", title: "Não entendi",
                            detail: "Diga, por exemplo, \"abrir Safari\" ou \"pesquisar contrato\".", webQuery: nil)
        }

        // Pesquisa na internet: tem "na internet", "no google"…
        var isWeb = false
        for phrase in webPhrases where remove(phrase, from: &words, folded: &folded) {
            isWeb = true
        }
        if folded.first == "google" || folded.first == "googlar" { isWeb = true }

        var verb: Verb?
        if let first = folded.first, let found = verbs[first] {
            verb = found
            words.removeFirst(); folded.removeFirst()
            // "onde está…" vira pesquisa
        } else if folded.count >= 2, folded[0] == "onde", folded[1] == "esta" || folded[1] == "fica" {
            verb = .search
            words.removeFirst(2); folded.removeFirst(2)
        } else if folded.first == "google" || folded.first == "googlar" {
            words.removeFirst(); folded.removeFirst()
        }

        // Dica de tipo: "pasta", "arquivo", "app"
        var kind: Spotlight.Kind?
        if let first = folded.first {
            if ["pasta", "diretorio", "folder"].contains(first) { kind = .folder }
            if ["arquivo", "documento", "ficheiro", "file"].contains(first) { kind = .file }
            if ["app", "aplicativo", "aplicacao", "programa"].contains(first) { kind = .app }
        }

        trimTargetFillers(&words, &folded)
        let target = words.joined(separator: " ")
        let foldedTarget = folded.joined(separator: " ")

        if isWeb {
            return web(target.isEmpty ? text : target)
        }

        switch verb {
        case .pause:
            if SpotifyController.shared.isPlaying { SpotifyController.shared.playPause() }
            return .music(title: "Música pausada", detail: SpotifyController.shared.track?.name ?? "")
        case .next:
            SpotifyController.shared.next()
            return .music(title: "Próxima música", detail: "")
        case .previous:
            SpotifyController.shared.previous()
            return .music(title: "Música anterior", detail: "")
        case .play:
            return await play(target)
        case .open:
            return await open(target, folded: foldedTarget, kind: kind)
        case .search:
            if target.isEmpty {
                return .message(symbol: "magnifyingglass", title: "Pesquisar o quê?",
                                detail: "Diga \"pesquisar\" seguido do nome do arquivo, pasta ou app.", webQuery: nil)
            }
            let found = await Spotlight.search(target, kind: kind)
            if found.isEmpty {
                return .message(symbol: "magnifyingglass", title: "Nada encontrado no Mac",
                                detail: "Não achei \"\(target)\" nos seus arquivos.", webQuery: target)
            }
            return .items(title: "Resultados para \"\(target)\"", items: found, webQuery: target)
        case nil:
            break
        }

        // Sem verbo: informação do sistema, app pelo nome ou pesquisa.
        if let info = SystemInfo.answer(for: folded.joined(separator: " ")) {
            return info
        }
        if let browser = defaultBrowser(for: foldedTarget) {
            NSWorkspace.shared.openApplication(at: browser, configuration: NSWorkspace.OpenConfiguration(), completionHandler: nil)
            return .opened(name: FileManager.default.displayName(atPath: browser.path).replacingOccurrences(of: ".app", with: ""),
                           url: browser, detail: "Navegador aberto")
        }
        if let app = AppIndex.find(foldedTarget) {
            NSWorkspace.shared.openApplication(at: app.url, configuration: NSWorkspace.OpenConfiguration(), completionHandler: nil)
            return .opened(name: app.name, url: app.url, detail: "App aberto")
        }
        let found = await Spotlight.search(target, kind: kind)
        if found.isEmpty {
            return .message(symbol: "questionmark.bubble", title: "Não encontrei \"\(target)\"",
                            detail: "Tente \"abrir…\", \"pesquisar…\" ou pesquise na internet.", webQuery: target)
        }
        return .items(title: "Resultados para \"\(target)\"", items: found, webQuery: target)
    }

    // MARK: - Ações

    private static func web(_ query: String) -> CommandResult {
        openWeb(query)
        return .opened(name: query, url: nil, detail: "Pesquisando na internet")
    }

    static func openWeb(_ query: String) {
        var components = URLComponents(string: "https://www.google.com/search")!
        components.queryItems = [URLQueryItem(name: "q", value: query)]
        if let url = components.url { NSWorkspace.shared.open(url) }
    }

    private static func play(_ query: String) async -> CommandResult {
        let spotify = SpotifyController.shared
        if query.isEmpty {
            if !spotify.isRunning { spotify.openApp() }
            else if !spotify.isPlaying { spotify.playPause() }
            return .music(title: "Tocando", detail: spotify.track?.name ?? "Spotify")
        }
        let liked = ["musicas curtidas", "curtidas", "minhas curtidas", "liked songs", "favoritas", "minhas favoritas",
                     "musicas favoritas", "as curtidas", "as musicas curtidas"]
        if liked.contains(fold(query)) {
            if SpotifyAPI.shared.isConnected && SpotifyAPI.shared.likedCollectionURI == nil {
                await SpotifyAPI.shared.loadLiked()
            }
            spotify.playLikedSongs()
            return .music(title: "Tocando Músicas Curtidas", detail: "")
        }
        let api = SpotifyAPI.shared
        if api.isConnected, let first = await api.search(query).first {
            spotify.play(uri: first.uri)
            return .music(title: "Tocando \(first.name)", detail: first.subtitle)
        }
        spotify.openSearch(query)
        return .music(title: "Buscando \"\(query)\" no Spotify",
                      detail: api.isConnected ? "" : "Conecte o Spotify nos Ajustes para tocar direto.")
    }

    private static func open(_ target: String, folded: String, kind: Spotlight.Kind?) async -> CommandResult {
        guard !target.isEmpty else {
            return .message(symbol: "questionmark.bubble", title: "Abrir o quê?",
                            detail: "Diga \"abrir\" seguido do nome de um app, pasta ou arquivo.", webQuery: nil)
        }

        if let browser = defaultBrowser(for: folded) {
            NSWorkspace.shared.openApplication(at: browser, configuration: NSWorkspace.OpenConfiguration(), completionHandler: nil)
            return .opened(name: FileManager.default.displayName(atPath: browser.path).replacingOccurrences(of: ".app", with: ""),
                           url: browser, detail: "Navegador aberto")
        }

        if kind != .app && kind != .file, let folder = folderAlias(folded) {
            NSWorkspace.shared.open(folder)
            return .opened(name: FileManager.default.displayName(atPath: folder.path), url: folder, detail: "Pasta aberta")
        }

        if kind == nil || kind == .app, let app = AppIndex.find(folded) {
            NSWorkspace.shared.openApplication(at: app.url, configuration: NSWorkspace.OpenConfiguration(), completionHandler: nil)
            return .opened(name: app.name, url: app.url, detail: "App aberto")
        }

        let found = await Spotlight.search(target, kind: kind)
        let foldedName = fold(target)
        if let exact = found.first(where: { fold($0.name) == foldedName || fold(($0.name as NSString).deletingPathExtension) == foldedName })
            ?? (found.count == 1 ? found.first : nil) {
            NSWorkspace.shared.open(exact.url)
            return .opened(name: exact.name, url: exact.url, detail: exact.kind)
        }
        if found.isEmpty {
            return .message(symbol: "questionmark.folder", title: "Não encontrei \"\(target)\"",
                            detail: "Não há app, pasta ou arquivo com esse nome.", webQuery: target)
        }
        return .items(title: "Qual destes?", items: found, webQuery: nil)
    }

    /// "navegador", "browser", "internet" abrem o navegador padrão (ex.: Chrome).
    private static func defaultBrowser(for folded: String) -> URL? {
        guard ["navegador", "o navegador", "browser", "internet", "a internet", "web"].contains(folded) else { return nil }
        return NSWorkspace.shared.urlForApplication(toOpen: URL(string: "https://www.apple.com")!)
    }

    private static func folderAlias(_ folded: String) -> URL? {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        func dir(_ d: FileManager.SearchPathDirectory) -> URL? { fm.urls(for: d, in: .userDomainMask).first }
        switch folded {
        case "downloads", "transferencias", "download": return dir(.downloadsDirectory)
        case "documentos", "documents", "meus documentos": return dir(.documentDirectory)
        case "mesa", "area de trabalho", "desktop", "secretaria": return dir(.desktopDirectory)
        case "aplicativos", "aplicacoes", "applications", "apps": return URL(fileURLWithPath: "/Applications")
        case "imagens", "pictures": return dir(.picturesDirectory)
        case "filmes", "videos", "movies": return dir(.moviesDirectory)
        case "musicas", "music": return dir(.musicDirectory)
        case "lixeira", "lixo", "trash": return home.appendingPathComponent(".Trash")
        case "inicio", "pasta pessoal", "home", "pasta de inicio": return home
        case "icloud", "icloud drive": return home.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs")
        default: return nil
        }
    }

    // MARK: - Texto

    static func fold(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "pt_BR"))
            .lowercased()
            .trimmingCharacters(in: .punctuationCharacters.union(.whitespaces))
    }

    private static func remove(_ phrase: [String], from words: inout [String], folded: inout [String]) -> Bool {
        guard phrase.count <= folded.count else { return false }
        for start in 0...(folded.count - phrase.count) where Array(folded[start..<start + phrase.count]) == phrase {
            words.removeSubrange(start..<start + phrase.count)
            folded.removeSubrange(start..<start + phrase.count)
            return true
        }
        return false
    }

    private static func trimTargetFillers(_ words: inout [String], _ folded: inout [String]) {
        let kindWords: Set<String> = ["pasta", "diretorio", "folder", "arquivo", "documento", "ficheiro", "file"]
        while let first = folded.first, targetFillers.contains(first) || kindWords.contains(first) {
            words.removeFirst(); folded.removeFirst()
        }
    }
}

// MARK: - Apps instalados

@MainActor
enum AppIndex {
    struct App {
        let url: URL
        let name: String
        let keys: [String]
    }

    private static var cache: [App] = []
    private static var builtAt = Date.distantPast

    private static let aliases: [String: String] = [
        "ajustes": "ajustes do sistema", "configuracoes": "ajustes do sistema",
        "preferencias": "ajustes do sistema", "preferencias do sistema": "ajustes do sistema",
        "settings": "system settings", "vscode": "visual studio code", "vs code": "visual studio code",
        "code": "visual studio code", "zap": "whatsapp", "whats": "whatsapp", "lol": "league of legends",
        "loja": "app store", "email": "mail", "e-mail": "mail"
    ]

    static var apps: [App] {
        if Date().timeIntervalSince(builtAt) > 300 || cache.isEmpty { rebuild() }
        return cache
    }

    static func find(_ query: String) -> App? {
        let q = aliases[query] ?? query
        guard !q.isEmpty else { return nil }
        let all = apps
        if let exact = all.first(where: { $0.keys.contains(q) }) { return exact }
        if let prefix = all.first(where: { $0.keys.contains { $0.hasPrefix(q) } }) { return prefix }
        guard q.count >= 3 else { return nil }
        return all.first(where: { $0.keys.contains { $0.contains(q) } })
    }

    private static func rebuild() {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser.path
        let roots = ["/Applications", "/System/Applications", "/System/Applications/Utilities",
                     home + "/Applications", "/System/Library/CoreServices/Applications"]
        var found: [URL] = []
        for root in roots {
            let url = URL(fileURLWithPath: root)
            guard let items = try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: nil) else { continue }
            for item in items {
                if item.pathExtension == "app" {
                    found.append(item)
                } else if let inner = try? fm.contentsOfDirectory(at: item, includingPropertiesForKeys: nil) {
                    found += inner.filter { $0.pathExtension == "app" }
                }
            }
        }
        found.append(URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app"))

        var seen = Set<String>()
        cache = found.compactMap { url in
            guard seen.insert(url.path).inserted else { return nil }
            var display = fm.displayName(atPath: url.path)
            if display.hasSuffix(".app") { display = String(display.dropLast(4)) }
            let fileName = url.deletingPathExtension().lastPathComponent
            let keys = Array(Set([CommandEngine.fold(display), CommandEngine.fold(fileName)]))
            return App(url: url, name: display, keys: keys)
        }
        // Nomes curtos primeiro, para "notas" achar Notas antes de "Notas Rápidas".
        cache.sort { $0.name.count < $1.name.count }
        builtAt = Date()
    }
}

// MARK: - Spotlight

@MainActor
enum Spotlight {
    enum Kind { case app, folder, file }

    private final class Box { var done = false }

    static func search(_ text: String, kind: Kind? = nil, limit: Int = 12) async -> [SearchItem] {
        let byName = await run(namePredicate(text, kind: kind), limit: limit, text: text)
        if !byName.isEmpty || kind == .app || kind == .folder { return byName }
        // Nada no nome: procura dentro do conteúdo dos documentos.
        let content = NSPredicate(format: "kMDItemTextContent CONTAINS[cd] %@", text)
        return await run(content, limit: limit, text: text)
    }

    private static func namePredicate(_ text: String, kind: Kind?) -> NSPredicate {
        let words = text.split(whereSeparator: \.isWhitespace).map(String.init)
        var parts = words.map { NSPredicate(format: "kMDItemDisplayName CONTAINS[cd] %@", $0) }
        switch kind {
        case .app: parts.append(NSPredicate(format: "kMDItemContentType == 'com.apple.application-bundle'"))
        case .folder: parts.append(NSPredicate(format: "kMDItemContentType == 'public.folder'"))
        case .file: parts.append(NSPredicate(format: "kMDItemContentType != 'public.folder'"))
        case nil: break
        }
        return NSCompoundPredicate(andPredicateWithSubpredicates: parts)
    }

    private static func run(_ predicate: NSPredicate, limit: Int, text: String) async -> [SearchItem] {
        let query = NSMetadataQuery()
        query.predicate = predicate
        query.searchScopes = [NSMetadataQueryLocalComputerScope]
        query.sortDescriptors = [NSSortDescriptor(key: NSMetadataItemLastUsedDateKey, ascending: false)]

        let box = Box()
        let items: [SearchItem] = await withCheckedContinuation { continuation in
            var observer: NSObjectProtocol?
            let finish: () -> Void = {
                guard !box.done else { return }
                box.done = true
                query.disableUpdates()
                query.stop()
                if let observer { NotificationCenter.default.removeObserver(observer) }
                continuation.resume(returning: collect(query, limit: limit, text: text))
            }
            observer = NotificationCenter.default.addObserver(forName: .NSMetadataQueryDidFinishGathering,
                                                              object: query, queue: .main) { _ in
                MainActor.assumeIsolated { finish() }
            }
            if !query.start() {
                finish()
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                MainActor.assumeIsolated { finish() }
            }
        }
        return items
    }

    private static func collect(_ query: NSMetadataQuery, limit: Int, text: String) -> [SearchItem] {
        let target = CommandEngine.fold(text)
        var items: [SearchItem] = []
        for index in 0..<min(query.resultCount, 300) {
            guard let result = query.result(at: index) as? NSMetadataItem,
                  let path = result.value(forAttribute: NSMetadataItemPathKey) as? String else { continue }
            // Ignora arquivos internos do sistema e de apps.
            if path.contains("/Library/") || path.contains("/.") || path.hasPrefix("/System/Library")
                || path.hasPrefix("/private") || path.contains(".app/") { continue }
            let name = result.value(forAttribute: NSMetadataItemDisplayNameKey) as? String
                ?? (path as NSString).lastPathComponent
            let kind = result.value(forAttribute: NSMetadataItemKindKey) as? String ?? ""
            items.append(SearchItem(url: URL(fileURLWithPath: path), name: name, kind: kind))
        }
        // Nome igual primeiro, depois começando com o termo.
        func rank(_ item: SearchItem) -> Int {
            let name = CommandEngine.fold((item.name as NSString).deletingPathExtension)
            if name == target { return 0 }
            if name.hasPrefix(target) { return 1 }
            return 2
        }
        let ranked = items.enumerated().sorted { a, b in
            let ra = rank(a.element), rb = rank(b.element)
            return ra == rb ? a.offset < b.offset : ra < rb
        }
        return Array(ranked.map(\.element).prefix(limit))
    }
}
