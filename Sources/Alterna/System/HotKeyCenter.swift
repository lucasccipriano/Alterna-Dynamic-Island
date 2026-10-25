import Carbon

/// Atalhos globais com RegisterEventHotKey (Carbon). Não exige permissão nenhuma.
/// Cada parte do app registra o seu grupo ("profiles", "app"…) sem apagar os outros.
@MainActor
final class HotKeyCenter {
    static let shared = HotKeyCenter()

    private static let signature: OSType = 0x414C_544E // "ALTN"

    private var groups: [String: [(Shortcut, () -> Void)]] = [:]
    private var refs: [EventHotKeyRef] = []
    private var actions: [UInt32: () -> Void] = [:]
    private var isSuspended = false

    private init() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), hotKeyHandler, 1, &spec, nil, nil)
    }

    func setBindings(_ newBindings: [(Shortcut, () -> Void)], group: String = "profiles") {
        groups[group] = newBindings
        if !isSuspended { registerAll() }
    }

    /// Usado enquanto o gravador de atalho está ativo, para a tecla não disparar uma ação.
    func suspend() {
        isSuspended = true
        unregisterAll()
    }

    func resume() {
        isSuspended = false
        registerAll()
    }

    fileprivate func fire(_ id: UInt32) {
        actions[id]?()
    }

    private func registerAll() {
        unregisterAll()
        let all = groups.keys.sorted().flatMap { groups[$0] ?? [] }
        for (index, (shortcut, action)) in all.enumerated() {
            let id = UInt32(index + 1)
            var ref: EventHotKeyRef?
            let status = RegisterEventHotKey(shortcut.keyCode,
                                             shortcut.modifiers,
                                             EventHotKeyID(signature: Self.signature, id: id),
                                             GetApplicationEventTarget(),
                                             0,
                                             &ref)
            if status == noErr, let ref {
                refs.append(ref)
                actions[id] = action
            } else {
                NSLog("Alterna: atalho \(shortcut.display) já está em uso (\(status))")
            }
        }
    }

    private func unregisterAll() {
        for ref in refs { UnregisterEventHotKey(ref) }
        refs.removeAll()
        actions.removeAll()
    }
}

private func hotKeyHandler(_ next: EventHandlerCallRef?,
                           _ event: EventRef?,
                           _ userData: UnsafeMutableRawPointer?) -> OSStatus {
    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(event,
                                   EventParamName(kEventParamDirectObject),
                                   EventParamType(typeEventHotKeyID),
                                   nil,
                                   MemoryLayout<EventHotKeyID>.size,
                                   nil,
                                   &hotKeyID)
    guard status == noErr else { return status }
    let id = hotKeyID.id
    Task { @MainActor in HotKeyCenter.shared.fire(id) }
    return noErr
}
