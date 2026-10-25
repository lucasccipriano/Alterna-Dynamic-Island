import Foundation
import IOKit.ps

/// Respostas rápidas sobre o Mac: bateria, armazenamento, memória, sistema, hora.
enum SystemInfo {
    /// `text` já vem sem acentos e em minúsculas.
    static func answer(for text: String) -> CommandResult? {
        let t = " \(text) "
        if t.contains("bateria") || t.contains("battery") || t.contains("carga") {
            return battery()
        }
        if t.contains("armazenamento") || t.contains("espaco") || t.contains(" disco") || t.contains("storage") {
            return storage()
        }
        if t.contains("memoria") || t.contains(" ram ") || t.contains("memory") {
            return memory()
        }
        if t.contains("versao") || t.contains("macos") || t.contains("sobre este mac")
            || t.contains("meu mac") || t.contains("sistema") {
            return system()
        }
        if t.contains("que horas") || t.contains(" hora ") || t.contains(" horas ") {
            let f = DateFormatter()
            f.locale = Locale(identifier: "pt_BR")
            f.dateFormat = "HH:mm"
            return .info(symbol: "clock.fill", title: "Hora", value: f.string(from: Date()), detail: nil)
        }
        if t.contains("que dia") || t.contains("data de hoje") || t.contains(" hoje ") || t.contains(" data ") {
            let f = DateFormatter()
            f.locale = Locale(identifier: "pt_BR")
            f.dateStyle = .full
            return .info(symbol: "calendar", title: "Hoje", value: f.string(from: Date()), detail: nil)
        }
        return nil
    }

    /// Nível rápido para a linha do notch.
    static func batteryLevel() -> (percent: Int, charging: Bool, symbol: String)? {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for source in list {
            guard let info = IOPSGetPowerSourceDescription(blob, source)?.takeUnretainedValue() as? [String: Any],
                  let current = info["Current Capacity"] as? Int,
                  let maximum = info["Max Capacity"] as? Int, maximum > 0 else { continue }
            let percent = current * 100 / maximum
            let charging = info["Is Charging"] as? Bool ?? false
            let symbol: String
            if charging { symbol = "battery.100percent.bolt" }
            else if percent < 15 { symbol = "battery.0percent" }
            else if percent < 40 { symbol = "battery.25percent" }
            else if percent < 65 { symbol = "battery.50percent" }
            else if percent < 90 { symbol = "battery.75percent" }
            else { symbol = "battery.100percent" }
            return (percent, charging, symbol)
        }
        return nil
    }

    static func battery() -> CommandResult {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] else {
            return .info(symbol: "powerplug.fill", title: "Bateria", value: "Sem bateria", detail: "Este Mac usa a tomada.")
        }
        for source in list {
            guard let info = IOPSGetPowerSourceDescription(blob, source)?.takeUnretainedValue() as? [String: Any],
                  let current = info["Current Capacity"] as? Int,
                  let maximum = info["Max Capacity"] as? Int, maximum > 0 else { continue }
            let percent = current * 100 / maximum
            let charging = info["Is Charging"] as? Bool ?? false
            let onAC = (info["Power Source State"] as? String) == "AC Power"
            var detail = charging ? "Carregando" : (onAC ? "Na tomada" : "Na bateria")
            if !charging, !onAC, let minutes = info["Time to Empty"] as? Int, minutes > 0 {
                detail += " · cerca de \(minutes / 60)h\(String(format: "%02d", minutes % 60)) restantes"
            }
            let symbol: String
            switch percent {
            case ..<15: symbol = "battery.0percent"
            case ..<40: symbol = "battery.25percent"
            case ..<65: symbol = "battery.50percent"
            case ..<90: symbol = "battery.75percent"
            default: symbol = "battery.100percent"
            }
            return .info(symbol: charging ? "battery.100percent.bolt" : symbol,
                         title: "Bateria", value: "\(percent)%", detail: detail)
        }
        return .info(symbol: "powerplug.fill", title: "Bateria", value: "Sem bateria", detail: nil)
    }

    static func storage() -> CommandResult {
        let url = URL(fileURLWithPath: "/")
        let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey])
        let free = values?.volumeAvailableCapacityForImportantUsage ?? 0
        let total = Int64(values?.volumeTotalCapacity ?? 0)
        let f = ByteCountFormatter()
        f.countStyle = .file
        return .info(symbol: "internaldrive.fill", title: "Armazenamento",
                     value: "\(f.string(fromByteCount: free)) livres",
                     detail: total > 0 ? "de \(f.string(fromByteCount: total))" : nil)
    }

    static func memory() -> CommandResult {
        let total = ProcessInfo.processInfo.physicalMemory
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let status = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        let f = ByteCountFormatter()
        f.countStyle = .memory
        var detail = "de \(f.string(fromByteCount: Int64(total)))"
        var value = f.string(fromByteCount: Int64(total))
        if status == KERN_SUCCESS {
            let page = UInt64(vm_kernel_page_size)
            let used = (UInt64(stats.active_count) + UInt64(stats.wire_count) + UInt64(stats.compressor_page_count)) * page
            value = "\(f.string(fromByteCount: Int64(used))) em uso"
        } else {
            detail = "instalados"
        }
        return .info(symbol: "memorychip.fill", title: "Memória", value: value, detail: detail)
    }

    static func system() -> CommandResult {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        let version = "macOS \(v.majorVersion).\(v.minorVersion)" + (v.patchVersion > 0 ? ".\(v.patchVersion)" : "")
        let name = Host.current().localizedName ?? "Este Mac"
        let uptime = Int(ProcessInfo.processInfo.systemUptime)
        let days = uptime / 86_400, hours = (uptime % 86_400) / 3600
        let chip = sysctlString("machdep.cpu.brand_string") ?? ""
        let up = days > 0 ? "ligado há \(days)d \(hours)h" : "ligado há \(hours)h"
        return .info(symbol: "laptopcomputer", title: name, value: version,
                     detail: [chip, up].filter { !$0.isEmpty }.joined(separator: " · "))
    }

    private static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        return String(cString: buffer)
    }
}
