import CoreGraphics

/// Синтез клавиатурных событий: отдельные клавиши (delete/enter) и комбинации (cmd+C).
/// События помечаются `eventSourceUserData`, чтобы EventTap не обрабатывал их повторно.
public enum EventSynth: Sendable {
    private static func makeEvent(
        keycode: UInt16,
        keyDown: Bool,
        flags: CGEventFlags = [],
        sourceID: CGEventSourceStateID
    ) -> CGEvent? {
        let source = CGEventSource(stateID: sourceID)
        let event = CGEvent(keyboardEventSource: source, virtualKey: keycode, keyDown: keyDown)
        event?.flags = flags
        event?.setIntegerValueField(.eventSourceUserData, value: EventTap.ownEventUserData)
        return event
    }

    public static func pressKey(_ keycode: UInt16, sourceID: CGEventSourceStateID? = nil) {
        let sid = sourceID ?? .combinedSessionState
        makeEvent(keycode: keycode, keyDown: true, sourceID: sid)?.post(tap: .cghidEventTap)
        makeEvent(keycode: keycode, keyDown: false, sourceID: sid)?.post(tap: .cghidEventTap)
    }

    public static func pressKeyCombination(_ modifiers: CGEventFlags, key: UInt16) {
        makeEvent(keycode: key, keyDown: true, flags: modifiers, sourceID: .combinedSessionState)?
            .post(tap: .cghidEventTap)
        makeEvent(keycode: key, keyDown: false, sourceID: .combinedSessionState)?
            .post(tap: .cghidEventTap)
    }
}
