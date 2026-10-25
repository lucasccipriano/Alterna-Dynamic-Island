import Foundation

/// Atalho global. `modifiers` usa as máscaras do Carbon (cmdKey, optionKey…).
struct Shortcut: Codable, Hashable {
    var keyCode: UInt32
    var modifiers: UInt32
    var display: String
}

/// Um perfil guarda só o que deve mudar. `nil` significa "não alterar".
struct Profile: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    var symbol: String = "person.fill"
    var shortcut: Shortcut?

    var inputSourceID: String?
    var naturalScrolling: Bool?
    var reverseMouseWheel: Bool?
    var mouseSpeed: Double?
    var trackpadSpeed: Double?
}

extension Profile {
    /// Resumo curto mostrado no menu.
    var summary: String {
        var parts: [String] = []
        if let id = inputSourceID {
            parts.append(InputSources.name(for: id) ?? "Teclado")
        }
        if let natural = naturalScrolling {
            parts.append(natural ? "Rolagem natural" : "Rolagem padrão")
        }
        if reverseMouseWheel == true {
            parts.append("Mouse invertido")
        }
        if mouseSpeed != nil || trackpadSpeed != nil {
            parts.append("Velocidade")
        }
        return parts.isEmpty ? "Sem alterações" : parts.joined(separator: " · ")
    }
}
