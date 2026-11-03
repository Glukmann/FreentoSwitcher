import AppKit
import ApplicationServices

/// Опрос наличия текстового выделения в фокусном приложении через Accessibility API.
/// nil = определить не удалось (приложение не отдало атрибуты) — caller использует fallback.
public enum SelectionProbe: Sendable {
    public static func hasSelection() -> Bool? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        // Таймаут 1 c (per-element): зависшее фронт-приложение иначе
        // подвесит обработку клавиш до системного таймаута тапа.
        AXUIElementSetMessagingTimeout(axApp, 1)
        var focusedRef: CFTypeRef?
        // Кривое AX-приложение может вернуть не-element: в Swift 6 `as?` к CF-типу
        // не компилируется («always succeed»), безусловный `as` — тоже, поэтому
        // проверяем typeID (как для rangeRef ниже) — после неё as! безопасен.
        guard AXUIElementCopyAttributeValue(axApp, kAXFocusedUIElementAttribute as CFString, &focusedRef) == .success,
              let focusedRef,
              CFGetTypeID(focusedRef) == AXUIElementGetTypeID() else { return nil }
        let focused = focusedRef as! AXUIElement
        AXUIElementSetMessagingTimeout(focused, 1)
        var rangeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(focused, kAXSelectedTextRangeAttribute as CFString, &rangeRef) == .success,
              let rangeRef,
              CFGetTypeID(rangeRef) == AXValueGetTypeID() else { return nil }
        let rangeValue = rangeRef as! AXValue
        var range = CFRange()
        guard AXValueGetValue(rangeValue, .cfRange, &range) else { return nil }
        return range.length > 0
    }
}
