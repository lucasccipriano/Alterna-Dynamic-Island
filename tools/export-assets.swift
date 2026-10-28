// Exporta do Mac os recursos visuais usados no vídeo de demonstração:
// símbolos SF (os mesmos da ilha), cursores do macOS, papel de parede atual,
// ícones de apps e a geometria do notch.
// Uso: swift export-assets.swift <pasta-de-saída>
import AppKit

let out = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "video-assets")
let fm = FileManager.default
try? fm.createDirectory(at: out.appendingPathComponent("symbols"), withIntermediateDirectories: true)
try? fm.createDirectory(at: out.appendingPathComponent("apps"), withIntermediateDirectories: true)

func savePNG(_ image: NSImage, size: NSSize, to url: URL) {
    guard size.width >= 1, size.height >= 1 else { print("tamanho inválido: \(url.lastPathComponent)"); return }
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return }
    rep.size = size
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    image.draw(in: NSRect(origin: .zero, size: size))
    NSGraphicsContext.restoreGraphicsState()
    try? rep.representation(using: .png, properties: [:])?.write(to: url)
}

// Símbolos SF, brancos, em alta resolução
let symbols = [
    "music.note", "bell.fill", "bell.badge.fill", "waveform", "switch.2", "antenna.radiowaves.left.and.right",
    "gearshape.fill", "play.fill", "pause.fill", "backward.fill", "forward.fill", "shuffle", "repeat",
    "speaker.wave.3.fill", "speaker.fill", "mic.fill", "mic.slash.fill", "heart.fill", "checkmark.circle.fill",
    "briefcase.fill", "gamecontroller.fill", "keyboard", "keyboard.fill", "airpodspro", "computermouse.fill",
    "headphones", "battery.100percent", "battery.75percent", "line.3.horizontal.decrease.circle", "xmark",
    "plus", "magnifyingglass", "globe", "text.cursor", "music.note.list", "play.circle.fill", "wifi",
    "chevron.down", "checkmark", "capsule.fill"
]
var manifest: [String: [String: Double]] = [:]
for name in symbols where !fm.fileExists(atPath: out.appendingPathComponent("symbols/\(name)-bold.png").path) || true {
    for weight in [("semibold", NSFont.Weight.semibold), ("medium", NSFont.Weight.medium), ("bold", NSFont.Weight.bold)] {
        let config = NSImage.SymbolConfiguration(pointSize: 96, weight: weight.1)
            .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
        guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(config) else { print("sem símbolo: \(name)"); continue }
        let size = NSSize(width: ceil(image.size.width), height: ceil(image.size.height))
        savePNG(image, size: NSSize(width: size.width * 2, height: size.height * 2),
                to: out.appendingPathComponent("symbols/\(name)-\(weight.0).png"))
        manifest[name] = ["w": size.width / 96, "h": size.height / 96]
    }
}
if let data = try? JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys]) {
    try? data.write(to: out.appendingPathComponent("symbols/manifest.json"))
}

// Cursores do macOS
for (name, cursor) in [("arrow", NSCursor.arrow), ("hand", NSCursor.pointingHand)] {
    let img = cursor.image
    var base = img.size
    if base.width < 1 { base = img.representations.first.map { NSSize(width: $0.pixelsWide / 2, height: $0.pixelsHigh / 2) } ?? NSSize(width: 32, height: 32) }
    if base.width < 1 { base = NSSize(width: 32, height: 32) }
    savePNG(img, size: NSSize(width: base.width * 4, height: base.height * 4),
            to: out.appendingPathComponent("cursor-\(name).png"))
    let hot = cursor.hotSpot
    let info = ["w": base.width, "h": base.height, "hx": hot.x, "hy": hot.y]
    if let d = try? JSONSerialization.data(withJSONObject: info) {
        try? d.write(to: out.appendingPathComponent("cursor-\(name).json"))
    }
}

// Ícones de apps (para as notificações)
for (file, bundle) in [("calendar", "com.apple.iCal"), ("messages", "com.apple.MobileSMS"), ("mail", "com.apple.mail")] {
    if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle) {
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        savePNG(icon, size: NSSize(width: 256, height: 256), to: out.appendingPathComponent("apps/\(file).png"))
    }
}

// Tela, notch e papel de parede
if let screen = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.main {
    var info: [String: Double] = ["width": screen.frame.width, "height": screen.frame.height,
                                  "scale": screen.backingScaleFactor,
                                  "menubar": Double(NSStatusBar.system.thickness)]
    if screen.safeAreaInsets.top > 0, let l = screen.auxiliaryTopLeftArea, let r = screen.auxiliaryTopRightArea {
        info["notchWidth"] = screen.frame.width - l.width - r.width
        info["notchHeight"] = screen.safeAreaInsets.top
    }
    if let d = try? JSONSerialization.data(withJSONObject: info, options: .prettyPrinted) {
        try? d.write(to: out.appendingPathComponent("screen.json"))
    }
    if let wall = NSWorkspace.shared.desktopImageURL(for: screen), let img = NSImage(contentsOf: wall) {
        let px = NSSize(width: screen.frame.width * 2, height: screen.frame.height * 2)
        savePNG(img, size: px, to: out.appendingPathComponent("wallpaper.png"))
    }
}

// Fonte do sistema (SF Pro), para o texto ficar igual ao do Mac
for path in ["/System/Library/Fonts/SFNS.ttf", "/System/Library/Fonts/SFNSRounded.ttf"] {
    let src = URL(fileURLWithPath: path)
    try? fm.removeItem(at: out.appendingPathComponent(src.lastPathComponent))
    try? fm.copyItem(at: src, to: out.appendingPathComponent(src.lastPathComponent))
}
print("Pronto: \(out.path)")
