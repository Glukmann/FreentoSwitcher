import CoreGraphics
import Carbon // IsSecureEventInputEnabled

public struct KeyEvent: Sendable {
    public var keycode: UInt16
    public var modifiers: UInt64
    public var type: EventType

    public enum EventType: Sendable {
        case keyDown, keyUp
    }
}

public protocol EventTapDelegate: AnyObject {
    func eventTap(_ tap: EventTap, didReceiveKey key: KeyEvent) -> Bool
    /// true = пропустить событие дальше (return event), false = поглотить (return nil)
}

public final class EventTap: @unchecked Sendable {
    public weak var delegate: EventTapDelegate?
    private var machPort: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    /// Mark for our own synthesized events so we don't re-ingest them.
    static let ownEventUserData: Int64 = 0xF3E9A11

    public init() {}

    deinit {
        stop()
    }

    public func start() -> Bool {
        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon else { return Unmanaged.passRetained(event) }
            let tap = Unmanaged<EventTap>.fromOpaque(refcon).takeUnretainedValue()
            return tap.handleEvent(type: type, event: event)
        }
        // .defaultTap (не .listenOnly): в Plan B конвертация выделения будет поглощать
        // события (return nil), listenOnly-тап этого не умеет.
        guard let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask((1 << CGEventType.keyDown.rawValue)
                | (1 << CGEventType.keyUp.rawValue)
                | (1 << CGEventType.flagsChanged.rawValue)),
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return false }
        machPort = port
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        return true
    }

    public func stop() {
        if let port = machPort { CGEvent.tapEnable(tap: port, enable: false) }
        if let src = runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetCurrent(), src, .commonModes) }
        machPort = nil
        runLoopSource = nil
    }

    public var isSecureInputWarningNeeded: Bool {
        IsSecureEventInputEnabled()
    }

    /// Модификаторы приходят не keyDown/keyUp, а flagsChanged — без перевода
    /// переходов в KeyEvent делегат не видит «чистых» нажатий Option/Shift/...
    /// (хоткей «одиночный Option» физически недостижим).
    private var lastFlags: UInt64 = 0

    private func modifierFlagBit(for keycode: UInt16) -> UInt64? {
        switch keycode {
        case 0x39: return 1 << 16                 // Caps Lock
        case 0x38, 0x3C: return 1 << 17           // Shift
        case 0x3B, 0x3E: return 1 << 18           // Control
        case 0x3A, 0x3D: return 1 << 19           // Option
        case 0x37, 0x36: return 1 << 20           // Command
        case 0x3F: return 1 << 24                 // Fn
        default: return nil
        }
    }

    private func handleFlagsChanged(_ event: CGEvent) -> Unmanaged<CGEvent>? {
        let flags = UInt64(event.flags.rawValue)
        let keycode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        defer { lastFlags = flags }
        guard let bit = modifierFlagBit(for: keycode),
              (flags & bit) != (lastFlags & bit) else {
            return Unmanaged.passRetained(event)
        }
        let key = KeyEvent(
            keycode: keycode,
            modifiers: flags,
            type: (flags & bit) != 0 ? .keyDown : .keyUp)
        let passThrough = delegate?.eventTap(self, didReceiveKey: key) ?? true
        return passThrough ? Unmanaged.passRetained(event) : nil
    }

    private func handleEvent(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            DebugLogger.log("tap disabled type=\(type.rawValue), re-enabling")
            if let port = machPort { CGEvent.tapEnable(tap: port, enable: true) }
            return nil
        }
        if event.getIntegerValueField(.eventSourceUserData) == Self.ownEventUserData {
            return Unmanaged.passRetained(event) // наши собственные события — не обрабатываем, но пропускаем
        }
        guard type == .keyDown || type == .keyUp || type == .flagsChanged else {
            return Unmanaged.passRetained(event)
        }
        if type == .flagsChanged {
            return handleFlagsChanged(event)
        }
        let key = KeyEvent(
            keycode: UInt16(event.getIntegerValueField(.keyboardEventKeycode)),
            modifiers: event.flags.rawValue,
            type: type == .keyDown ? .keyDown : .keyUp)
        let passThrough = delegate?.eventTap(self, didReceiveKey: key) ?? true
        return passThrough ? Unmanaged.passRetained(event) : nil
    }
}
