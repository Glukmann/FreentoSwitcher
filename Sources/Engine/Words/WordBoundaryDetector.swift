import Foundation

public struct WordBoundaryDetector: Sendable {
    /// Keycodes that finish a word and trigger the autocorrection check.
    /// ANSI: 0x31 space, 0x24 enter, 0x30 tab, 0x2B comma, 0x2F period,
    /// 0x2C slash, 0x29 semicolon, 0x27 quote, 0x1B hyphen.
    public static let separatorKeycodes: Set<UInt16> = [
        0x31, 0x24, 0x30, 0x2B, 0x2F, 0x2C, 0x29, 0x27, 0x1B,
    ]

    private let noAutoconvertAfterTabOrEnter: Bool

    public init(noAutoconvertAfterTabOrEnter: Bool) {
        self.noAutoconvertAfterTabOrEnter = noAutoconvertAfterTabOrEnter
    }

    /// Keycodes that finish a word and trigger the autocorrection check
    /// regardless of layout: 0x31 space, 0x24 enter, 0x30 tab.
    private static let universalSeparatorKeycodes: Set<UInt16> = [0x31, 0x24, 0x30]

    public func isWordSeparator(_ keycode: UInt16, englishLayout: Bool) -> Bool {
        if !englishLayout {
            // В русской раскладке клавиши пунктуации печатают буквы (э, б, ю, ж, ё-ряд)
            // и не должны разрывать слово.
            return Self.universalSeparatorKeycodes.contains(keycode)
        }
        if noAutoconvertAfterTabOrEnter && (keycode == 0x30 || keycode == 0x24) {
            return false
        }
        return Self.separatorKeycodes.contains(keycode)
    }
}
