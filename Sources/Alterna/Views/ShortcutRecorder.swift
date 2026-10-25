import AppKit
import Carbon
import SwiftUI

/// Campo para gravar um atalho, no estilo de Ajustes do Sistema › Teclado › Atalhos.
/// Clique, pressione a combinação. Esc cancela, Delete apaga.
struct ShortcutRecorder: View {
    @Binding var shortcut: Shortcut?
    @State private var isRecording = false
    @State private var monitor: Any?

    var body: some View {
        HStack(spacing: 4) {
            Button {
                isRecording ? stop() : start()
            } label: {
                Text(label)
                    .monospacedDigit()
                    .frame(minWidth: 130)
                    .foregroundStyle(isRecording ? Color.accentColor
                                     : (shortcut == nil ? Color.secondary : Color.primary))
            }
            .help(isRecording ? "Esc cancela · Delete apaga" : "Clique para gravar um atalho")

            if shortcut != nil, !isRecording {
                Button {
                    shortcut = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("Remover atalho")
            }
        }
        .onDisappear(perform: stop)
    }

    private var label: String {
        if isRecording { return "Digite o atalho…" }
        return shortcut?.display ?? "Gravar atalho"
    }

    private func start() {
        HotKeyCenter.shared.suspend()
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handle(event)
            return nil
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if isRecording {
            isRecording = false
            HotKeyCenter.shared.resume()
        }
    }

    private func handle(_ event: NSEvent) {
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        let code = Int(event.keyCode)

        if flags.isEmpty, code == kVK_Escape {
            stop()
            return
        }
        if flags.isEmpty, code == kVK_Delete || code == kVK_ForwardDelete {
            shortcut = nil
            stop()
            return
        }
        // Sem modificador só vale para teclas F (F1–F15), como no macOS.
        if flags.isEmpty, !Shortcut.isFunctionKey(code) {
            NSSound.beep()
            return
        }
        shortcut = Shortcut(event: event)
        stop()
    }
}

extension Shortcut {
    static let controlOptionCommand = UInt32(controlKey | optionKey | cmdKey)

    init(event: NSEvent) {
        let flags = event.modifierFlags
        var carbon: UInt32 = 0
        var text = ""
        // Ordem padrão da Apple: ⌃ ⌥ ⇧ ⌘
        if flags.contains(.control) { carbon |= UInt32(controlKey); text += "⌃" }
        if flags.contains(.option)  { carbon |= UInt32(optionKey);  text += "⌥" }
        if flags.contains(.shift)   { carbon |= UInt32(shiftKey);   text += "⇧" }
        if flags.contains(.command) { carbon |= UInt32(cmdKey);     text += "⌘" }
        text += Shortcut.keyName(Int(event.keyCode), characters: event.charactersIgnoringModifiers)
        self.init(keyCode: UInt32(event.keyCode), modifiers: carbon, display: text)
    }

    static func isFunctionKey(_ code: Int) -> Bool {
        functionKeys[code] != nil
    }

    private static func keyName(_ code: Int, characters: String?) -> String {
        if let name = functionKeys[code] ?? specialKeys[code] { return name }
        let chars = (characters ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return chars.isEmpty ? "?" : chars.uppercased()
    }

    private static let functionKeys: [Int: String] = [
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5",
        kVK_F6: "F6", kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10",
        kVK_F11: "F11", kVK_F12: "F12", kVK_F13: "F13", kVK_F14: "F14", kVK_F15: "F15"
    ]

    private static let specialKeys: [Int: String] = [
        kVK_Return: "↩", kVK_Tab: "⇥", kVK_Space: "Espaço",
        kVK_Delete: "⌫", kVK_ForwardDelete: "⌦", kVK_Escape: "⎋",
        kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_DownArrow: "↓", kVK_UpArrow: "↑",
        kVK_Home: "↖", kVK_End: "↘", kVK_PageUp: "⇞", kVK_PageDown: "⇟"
    ]
}
