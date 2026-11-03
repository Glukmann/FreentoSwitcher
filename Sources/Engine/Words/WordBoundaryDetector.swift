import Foundation

public struct WordBoundaryDetector: Sendable {
    /// Keycodes that finish a word and trigger the autocorrection check.
    /// Только пробельные клавиши: 0x31 space, 0x24 enter, 0x30 tab.
    /// Клавиши пунктуации (0x2B, 0x2F, 0x2C, 0x29, 0x27, 0x1B) слово НЕ рвут:
    /// в RU-раскладке они печатают буквы (э, б, ю, ж, ё-ряд), в EN — знаки,
    /// которые теперь копятся в буфере и конвертируются тождественно (как в Punto).
    public static let separatorKeycodes: Set<UInt16> = [
        0x31, 0x24, 0x30,
    ]

    private let noAutoconvertAfterTabOrEnter: Bool

    public init(noAutoconvertAfterTabOrEnter: Bool) {
        self.noAutoconvertAfterTabOrEnter = noAutoconvertAfterTabOrEnter
    }

    /// Разделители слова одинаковы для обеих раскладок: слово заканчивает
    /// только пробел/enter/tab.
    public func isWordSeparator(_ keycode: UInt16) -> Bool {
        if noAutoconvertAfterTabOrEnter && (keycode == 0x30 || keycode == 0x24) {
            return false
        }
        return Self.separatorKeycodes.contains(keycode)
    }
}
