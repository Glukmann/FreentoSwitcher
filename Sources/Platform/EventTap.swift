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

    private func handleEvent(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let port = machPort { CGEvent.tapEnable(tap: port, enable: true) }
            return nil
        }
        if event.getIntegerValueField(.eventSourceUserData) == Self.ownEventUserData {
            return Unmanaged.passRetained(event) // наши собственные события — не обрабатываем, но пропускаем
        }
        guard type == .keyDown || type == .keyUp else {
            return Unmanaged.passRetained(event)
        }
        let key = KeyEvent(
            keycode: UInt16(event.getIntegerValueField(.keyboardEventKeycode)),
            modifiers: event.flags.rawValue,
            type: type == .keyDown ? .keyDown : .keyUp)
        let passThrough = delegate?.eventTap(self, didReceiveKey: key) ?? true
        return passThrough ? Unmanaged.passRetained(event) : nil
    }
}
