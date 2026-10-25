import AppKit

/// Inverte só a roda do mouse, deixando o trackpad como está.
///
/// Rodas de mouse geram eventos "discretos"; trackpad (e Magic Mouse) geram eventos
/// "contínuos". Um event tap troca o sinal apenas dos discretos.
/// Requer permissão de Acessibilidade.
final class ScrollInverter {
    static let shared = ScrollInverter()

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    var isRunning: Bool { tap != nil }

    static var isTrusted: Bool { AXIsProcessTrusted() }

    static func requestPermission() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    @discardableResult
    func start() -> Bool {
        if tap != nil { return true }
        guard Self.isTrusted else { return false }

        let mask = CGEventMask(1 << CGEventType.scrollWheel.rawValue)
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap,
                                          place: .headInsertEventTap,
                                          options: .defaultTap,
                                          eventsOfInterest: mask,
                                          callback: scrollTapCallback,
                                          userInfo: nil) else { return false }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        self.tap = tap
        self.runLoopSource = source
        return true
    }

    func stop() {
        guard let tap else { return }
        CGEvent.tapEnable(tap: tap, enable: false)
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        CFMachPortInvalidate(tap)
        self.tap = nil
        self.runLoopSource = nil
    }

    fileprivate func reenable() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
    }
}

private func scrollTapCallback(proxy: CGEventTapProxy,
                               type: CGEventType,
                               event: CGEvent,
                               refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    switch type {
    case .tapDisabledByTimeout, .tapDisabledByUserInput:
        ScrollInverter.shared.reenable()
    case .scrollWheel:
        if event.getIntegerValueField(.scrollWheelEventIsContinuous) == 0 {
            invertScroll(event)
        }
    default:
        break
    }
    return Unmanaged.passUnretained(event)
}

private func invertScroll(_ event: CGEvent) {
    let axes: [(CGEventField, CGEventField, CGEventField)] = [
        (.scrollWheelEventDeltaAxis1, .scrollWheelEventPointDeltaAxis1, .scrollWheelEventFixedPtDeltaAxis1),
        (.scrollWheelEventDeltaAxis2, .scrollWheelEventPointDeltaAxis2, .scrollWheelEventFixedPtDeltaAxis2)
    ]
    for (delta, point, fixed) in axes {
        let d = event.getIntegerValueField(delta)
        let p = event.getIntegerValueField(point)
        let f = event.getDoubleValueField(fixed)
        event.setIntegerValueField(delta, value: -d)
        event.setIntegerValueField(point, value: -p)
        event.setDoubleValueField(fixed, value: -f)
    }
}
