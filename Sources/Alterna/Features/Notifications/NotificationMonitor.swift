import AppKit
import SQLite3
import SwiftUI

// MARK: - Modelo

struct NotificationItem: Identifiable, Equatable {
    let id: Int64
    let bundleID: String
    let title: String
    let subtitle: String
    let body: String
    let date: Date

    var appName: String { AppInfo.name(for: bundleID) }
    var category: NotificationCategory { NotificationCategory.of(bundleID) }
}

/// Tipos de notificação que podem ser ligados e desligados.
enum NotificationCategory: String, CaseIterable, Identifiable, Codable {
    case email, messages, social, calendar, browser, system, other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .email: "E-mail"
        case .messages: "Mensagens e chat"
        case .social: "Redes sociais"
        case .calendar: "Agenda e lembretes"
        case .browser: "Sites (navegadores)"
        case .system: "Sistema e apps da Apple"
        case .other: "Outros apps"
        }
    }

    var symbol: String {
        switch self {
        case .email: "envelope.fill"
        case .messages: "message.fill"
        case .social: "person.2.fill"
        case .calendar: "calendar"
        case .browser: "globe"
        case .system: "apple.logo"
        case .other: "app.badge.fill"
        }
    }

    var color: Color {
        switch self {
        case .email: .blue
        case .messages: .green
        case .social: .pink
        case .calendar: .red
        case .browser: .cyan
        case .system: .gray
        case .other: .orange
        }
    }

    private static let map: [String: NotificationCategory] = [
        // E-mail
        "com.apple.mail": .email, "com.microsoft.outlook": .email, "com.readdle.smartemail-mac": .email,
        "com.readdle.sparkdesktop": .email, "it.bloop.airmail2": .email, "com.superhuman.electron": .email,
        "com.mimestream.mimestream": .email, "com.freron.mailmate": .email, "com.postbox-inc.postbox": .email,
        "com.canarymail.mac": .email, "com.edisonmail.edisonmail": .email,
        // Mensagens
        "com.apple.ichat": .messages, "com.apple.mobilesms": .messages, "net.whatsapp.whatsapp": .messages,
        "desktop.whatsapp": .messages, "ru.keepcoder.telegram": .messages, "com.tdesktop.telegram": .messages,
        "com.tinyspeck.slackmacgap": .messages, "com.microsoft.teams": .messages, "com.microsoft.teams2": .messages,
        "com.hnc.discord": .messages, "org.whispersystems.signal-desktop": .messages,
        "com.facebook.archon": .messages, "com.facebook.archon.developerid": .messages,
        "jp.naver.line.mac": .messages, "com.tencent.xinwechat": .messages, "com.apple.facetime": .messages,
        "us.zoom.xos": .messages, "com.skype.skype": .messages,
        // Redes sociais
        "com.burbn.instagram": .social, "com.atebits.tweetie2": .social, "com.twitter.twitter-mac": .social,
        "maccatalyst.com.atebits.tweetie2": .social, "com.linkedin.linkedin": .social, "com.reddit.reddit": .social,
        "xyz.blueskyweb.app": .social, "com.tapbots.ivory": .social, "com.tapbots.ivorymac": .social,
        "com.zhiliaoapp.musically": .social, "com.pinterest": .social, "com.facebook.facebook": .social,
        "com.threads.app": .social, "com.joinmastodon.app": .social,
        // Agenda
        "com.apple.ical": .calendar, "com.apple.reminders": .calendar, "com.flexibits.fantastical2.mac": .calendar,
        "com.cron.electron": .calendar, "com.culturedcode.thingsmac": .calendar, "com.todoist.mac.todoist": .calendar,
        // Navegadores
        "com.google.chrome": .browser, "com.apple.safari": .browser, "org.mozilla.firefox": .browser,
        "company.thebrowser.browser": .browser, "com.microsoft.edgemac": .browser, "com.brave.browser": .browser,
        "com.operasoftware.opera": .browser, "com.vivaldi.vivaldi": .browser
    ]

    static func of(_ bundleID: String) -> NotificationCategory {
        let id = bundleID.lowercased()
        if let match = map[id] { return match }
        if id.hasPrefix("com.google.chrome.app.") { return .browser } // apps web do Chrome
        if id.hasPrefix("com.apple.") { return .system }
        return .other
    }
}

// MARK: - Leitor

/// Lê as notificações do banco da Central de Notificações do macOS.
///
/// O macOS não tem API para outros apps lerem notificações, então lemos uma cópia
/// do banco do `usernoted`. Isso exige Acesso Total ao Disco e pode mudar em
/// versões futuras do macOS.
@MainActor
final class NotificationMonitor: ObservableObject {
    static let shared = NotificationMonitor()

    @Published private(set) var items: [NotificationItem] = []
    @Published private(set) var hasAccess = true
    @Published private(set) var databaseFound = true
    /// Apps que já mandaram notificação (para a lista de filtros).
    @Published private(set) var knownApps: [String] = []

    @Published var disabledCategories: Set<NotificationCategory> {
        didSet { saveFilters() }
    }
    @Published var disabledApps: Set<String> {
        didSet { saveFilters() }
    }
    @Published var showBanners: Bool {
        didSet { UserDefaults.standard.set(showBanners, forKey: "notifications.banners") }
    }
    @Published var hiddenIDs: Set<Int64> = []

    private var lastRecordID: Int64 = 0
    private var lastStamp: Date?
    private var timer: Timer?
    private var isFirstLoad = true
    private let queue = DispatchQueue(label: "app.alterna.notifications", qos: .utility)

    private init() {
        let defaults = UserDefaults.standard
        let categories = defaults.stringArray(forKey: "notifications.disabledCategories") ?? []
        disabledCategories = Set(categories.compactMap(NotificationCategory.init(rawValue:)))
        disabledApps = Set(defaults.stringArray(forKey: "notifications.disabledApps") ?? [])
        showBanners = defaults.object(forKey: "notifications.banners") as? Bool ?? true
        knownApps = defaults.stringArray(forKey: "notifications.knownApps") ?? []
    }

    var visibleItems: [NotificationItem] {
        items.filter { isEnabled($0.bundleID) && !hiddenIDs.contains($0.id) }
    }

    func isEnabled(_ bundleID: String) -> Bool {
        !disabledApps.contains(bundleID) && !disabledCategories.contains(NotificationCategory.of(bundleID))
    }

    func setApp(_ bundleID: String, enabled: Bool) {
        if enabled { disabledApps.remove(bundleID) } else { disabledApps.insert(bundleID) }
    }

    func setCategory(_ category: NotificationCategory, enabled: Bool) {
        if enabled { disabledCategories.remove(category) } else { disabledCategories.insert(category) }
    }

    func clearAll() {
        hiddenIDs.formUnion(items.map(\.id))
    }

    func open(_ item: NotificationItem) {
        AppInfo.open(item.bundleID)
    }

    // MARK: - Leitura periódica

    func start() {
        guard timer == nil else { return }
        poll()
        timer = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.poll() }
        }
    }

    /// Pede de novo depois de dar o Acesso Total ao Disco.
    func retry() {
        lastStamp = nil
        poll()
    }

    private func poll() {
        let afterID = lastRecordID
        let stamp = lastStamp
        let limit = isFirstLoad ? 40 : 100
        queue.async {
            let result = NotificationDatabase.read(after: afterID, limit: limit, unchangedSince: stamp)
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self.apply(result) }
            }
        }
    }

    private func apply(_ result: NotificationDatabase.Result) {
        switch result {
        case .notFound:
            databaseFound = false
            hasAccess = true
        case .noAccess:
            databaseFound = true
            hasAccess = false
        case .unchanged:
            break
        case .records(let records, let stamp):
            hasAccess = true
            databaseFound = true
            lastStamp = stamp
            guard !records.isEmpty else { isFirstLoad = false; return }

            lastRecordID = max(lastRecordID, records.map(\.id).max() ?? 0)
            let newItems = records.sorted { $0.date > $1.date }
            items = Array((newItems + items).prefix(80))

            var known = Set(knownApps)
            known.formUnion(records.map(\.bundleID))
            if known.count != knownApps.count {
                knownApps = known.sorted { AppInfo.name(for: $0).localizedCompare(AppInfo.name(for: $1)) == .orderedAscending }
                UserDefaults.standard.set(knownApps, forKey: "notifications.knownApps")
            }

            // Só mostra banner do que chegou agora (não do carregamento inicial).
            if !isFirstLoad, showBanners,
               let latest = newItems.first(where: { isEnabled($0.bundleID) && Date().timeIntervalSince($0.date) < 30 }),
               !IslandModel.shared.isExpanded {
                IslandModel.shared.present(IslandActivity(
                    icon: .app(latest.bundleID),
                    title: latest.title.isEmpty ? latest.appName : latest.title,
                    subtitle: [latest.subtitle, latest.body].filter { !$0.isEmpty }.joined(separator: " — "),
                    duration: 4.5,
                    page: .notifications,
                    action: { AppInfo.open(latest.bundleID) }))
            }
            isFirstLoad = false
        }
    }

    private func saveFilters() {
        UserDefaults.standard.set(disabledCategories.map(\.rawValue), forKey: "notifications.disabledCategories")
        UserDefaults.standard.set(Array(disabledApps), forKey: "notifications.disabledApps")
    }
}

// MARK: - Acesso ao banco (fora da thread principal)

enum NotificationDatabase {
    enum Result {
        case notFound, noAccess, unchanged
        case records([NotificationItem], Date)
    }

    /// Caminhos conhecidos: macOS 15+ e versões anteriores.
    static var candidatePaths: [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        var paths = [home + "/Library/Group Containers/group.com.apple.usernoted/db2/db"]
        var buffer = [CChar](repeating: 0, count: Int(PATH_MAX))
        if confstr(_CS_DARWIN_USER_DIR, &buffer, buffer.count) > 0 {
            let dir = String(cString: buffer)
            paths.append(dir + "com.apple.notificationcenter/db2/db")
        }
        return paths
    }

    static func read(after lastID: Int64, limit: Int, unchangedSince stamp: Date?) -> Result {
        let fm = FileManager.default
        guard let path = candidatePaths.first(where: { fm.fileExists(atPath: $0) }) else { return .notFound }

        // Sem Acesso Total ao Disco, abrir o arquivo falha.
        guard let probe = FileHandle(forReadingAtPath: path) else { return .noAccess }
        try? probe.close()

        // Só relê quando o banco (ou o WAL) mudou.
        let modified = [path, path + "-wal"]
            .compactMap { (try? fm.attributesOfItem(atPath: $0))?[.modificationDate] as? Date }
            .max() ?? Date()
        if let stamp, modified <= stamp { return .unchanged }

        // Trabalha numa cópia para nunca travar nem alterar o banco do sistema.
        let temp = fm.temporaryDirectory.appendingPathComponent("alterna-notifications", isDirectory: true)
        try? fm.removeItem(at: temp)
        try? fm.createDirectory(at: temp, withIntermediateDirectories: true)
        let copy = temp.appendingPathComponent("db").path
        do {
            try fm.copyItem(atPath: path, toPath: copy)
            for suffix in ["-wal", "-shm"] where fm.fileExists(atPath: path + suffix) {
                try? fm.copyItem(atPath: path + suffix, toPath: copy + suffix)
            }
        } catch {
            return .noAccess
        }

        var db: OpaquePointer?
        guard sqlite3_open_v2(copy, &db, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK else {
            sqlite3_close(db)
            return .noAccess
        }
        defer { sqlite3_close(db) }

        let sql: String
        if lastID == 0 {
            sql = """
            SELECT r.rec_id, a.identifier, r.data, r.delivered_date FROM record r
            JOIN app a ON a.app_id = r.app_id ORDER BY r.rec_id DESC LIMIT \(limit)
            """
        } else {
            sql = """
            SELECT r.rec_id, a.identifier, r.data, r.delivered_date FROM record r
            JOIN app a ON a.app_id = r.app_id WHERE r.rec_id > \(lastID) ORDER BY r.rec_id DESC LIMIT \(limit)
            """
        }

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            return .records([], modified)
        }
        defer { sqlite3_finalize(statement) }

        var items: [NotificationItem] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let id = sqlite3_column_int64(statement, 0)
            let appID = sqlite3_column_text(statement, 1).map { String(cString: $0) } ?? ""
            let delivered = sqlite3_column_double(statement, 3)

            var title = "", subtitle = "", body = ""
            var bundleID = appID
            var date = Date(timeIntervalSinceReferenceDate: delivered)

            if let bytes = sqlite3_column_blob(statement, 2) {
                let length = Int(sqlite3_column_bytes(statement, 2))
                let data = Data(bytes: bytes, count: length)
                if let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] {
                    if let app = plist["app"] as? String, !app.isEmpty { bundleID = app }
                    if let req = plist["req"] as? [String: Any] {
                        title = req["titl"] as? String ?? ""
                        subtitle = req["subt"] as? String ?? ""
                        body = req["body"] as? String ?? ""
                    }
                    if delivered == 0, let raw = plist["date"] as? Double {
                        date = Date(timeIntervalSinceReferenceDate: raw)
                    }
                }
            }
            guard !bundleID.isEmpty, !(title.isEmpty && body.isEmpty) else { continue }
            items.append(NotificationItem(id: id, bundleID: bundleID, title: title,
                                          subtitle: subtitle, body: body, date: date))
        }
        return .records(items, modified)
    }
}
