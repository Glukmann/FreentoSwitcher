import AppKit
import ApplicationServices

/// Чтение/замена выделенного текста через Accessibility API.
/// Primary-путь конвертации выделения: атрибутная запись атомарна и не гоняет
/// буфер обмена (в отличие от paste→restore, где медленное приложение может
/// вставить уже восстановленный буфер). Буфер остаётся fallback'ом для
/// приложений, не отдающих kAXSelectedTextAttribute.
public enum AXSelection: Sendable {
    /// Выделенный текст фокусного элемента. nil = нет выделения ИЛИ приложение
    /// не отдало атрибут (caller решает: fallback на буфер или no-op).
    public static func readSelectedText() -> String? {
        guard let el = focusedElement() else { return nil }
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, kAXSelectedTextAttribute as CFString, &ref) == .success,
              let s = ref as? String, !s.isEmpty else { return nil }
        return s
    }

    /// Заменяет выделенный текст на `text` (атрибутная запись — атомарная замена:
    /// текст встаёт на место выделения, каретка — в конец вставленного).
    @discardableResult
    public static func replaceSelection(with text: String) -> Bool {
        guard let el = focusedElement() else { return false }
        let error = AXUIElementSetAttributeValue(el, kAXSelectedTextAttribute as CFString, text as CFString)
        return error == .success
    }

    /// Перевыделяет последние `utf16Count` символов перед текущей кареткой
    /// (каретка после replaceSelection стоит в конце вставленного текста).
    /// AX-диапазоны считаются в UTF-16 юнитах — передавай text.utf16.count.
    @discardableResult
    public static func reselectLast(_ utf16Count: Int) -> Bool {
        guard let el = focusedElement() else { return false }
        var rangeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, kAXSelectedTextRangeAttribute as CFString, &rangeRef) == .success,
              let rangeRef,
              CFGetTypeID(rangeRef) == AXValueGetTypeID() else { return false }
        var range = CFRange()
        guard AXValueGetValue(rangeRef as! AXValue, .cfRange, &range) else { return false }
        let length = min(utf16Count, range.location) // caret стоит в конце вставки
        guard length > 0 else { return false }
        var newRange = CFRange(location: range.location - length, length: length)
        guard let axRange = AXValueCreate(.cfRange, &newRange) else { return false }
        return AXUIElementSetAttributeValue(el, kAXSelectedTextRangeAttribute as CFString, axRange) == .success
    }

    private static func focusedElement() -> AXUIElement? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        // Таймаут 1 c (per-element): зависшее фронт-приложение иначе подвесит
        // обработку до системного таймаута тапа (как в SelectionProbe).
        AXUIElementSetMessagingTimeout(axApp, 1)
        var ref: CFTypeRef?
        // Кривое AX-приложение может вернуть не-element: проверяем typeID
        // (после неё as! безопасен), как для rangeRef выше и в SelectionProbe.
        guard AXUIElementCopyAttributeValue(axApp, kAXFocusedUIElementAttribute as CFString, &ref) == .success,
              let ref,
              CFGetTypeID(ref) == AXUIElementGetTypeID() else { return nil }
        let el = ref as! AXUIElement
        AXUIElementSetMessagingTimeout(el, 1)
        return el
    }
}
