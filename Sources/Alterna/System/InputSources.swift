import Carbon

struct InputSource: Identifiable, Hashable {
    let id: String      // ex.: com.apple.keylayout.Brazilian-ABNT2
    let name: String    // ex.: Português (Brasil)
}

/// Fontes de entrada do teclado via Text Input Sources (Carbon).
enum InputSources {
    /// Fontes ativadas em Ajustes do Sistema › Teclado › Fontes de Entrada.
    static func all() -> [InputSource] {
        sources().compactMap(makeSource)
    }

    static func current() -> InputSource? {
        makeSource(TISCopyCurrentKeyboardInputSource().takeRetainedValue())
    }

    static func name(for id: String) -> String? {
        all().first { $0.id == id }?.name
    }

    @discardableResult
    static func select(id: String) -> Bool {
        guard let source = sources().first(where: { sourceID($0) == id }) else { return false }
        return TISSelectInputSource(source) == noErr
    }

    // MARK: - Privado

    private static func sources() -> [TISInputSource] {
        let filter: [String: Any] = [
            key(kTISPropertyInputSourceCategory): key(kTISCategoryKeyboardInputSource),
            key(kTISPropertyInputSourceIsSelectCapable): true
        ]
        let list = TISCreateInputSourceList(filter as CFDictionary, false)?.takeRetainedValue()
        return (list as? [TISInputSource]) ?? []
    }

    private static func key(_ string: CFString) -> String { string as String }

    private static func sourceID(_ source: TISInputSource) -> String? {
        property(source, kTISPropertyInputSourceID)
    }

    private static func makeSource(_ source: TISInputSource) -> InputSource? {
        guard let id: String = property(source, kTISPropertyInputSourceID),
              let name: String = property(source, kTISPropertyLocalizedName) else { return nil }
        return InputSource(id: id, name: name)
    }

    private static func property<T>(_ source: TISInputSource, _ key: CFString) -> T? {
        guard let raw = TISGetInputSourceProperty(source, key) else { return nil }
        return Unmanaged<AnyObject>.fromOpaque(raw).takeUnretainedValue() as? T
    }
}
