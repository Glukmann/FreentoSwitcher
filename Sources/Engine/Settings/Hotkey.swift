import Foundation

public struct Hotkey: Codable, Equatable, Sendable {
    public var keycode: UInt16
    public var modifiers: UInt64

    public init(keycode: UInt16, modifiers: UInt64) {
        self.keycode = keycode
        self.modifiers = modifiers
    }

    public static let none = Hotkey(keycode: 0xFFFF, modifiers: 0)
}

public struct SoundMask: OptionSet, Codable, Equatable, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let switchToRussian   = SoundMask(rawValue: 1 << 0)
    public static let switchToEnglish   = SoundMask(rawValue: 1 << 1)
    public static let autoConvert       = SoundMask(rawValue: 1 << 2)
    public static let undo              = SoundMask(rawValue: 1 << 3)
    public static let selectionConvert  = SoundMask(rawValue: 1 << 4)
}
