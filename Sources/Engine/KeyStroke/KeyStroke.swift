public struct KeyStroke: Equatable, Codable, Sendable {
    public var keycode: UInt16
    public var modifiers: UInt64

    public init(keycode: UInt16, modifiers: UInt64) {
        self.keycode = keycode
        self.modifiers = modifiers
    }
}
