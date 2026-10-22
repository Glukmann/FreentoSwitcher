public struct KeyStrokeBuffer: Equatable, Sendable {
    public static let maxLength = 32

    /// Punctuation keycodes that act as word separators when counting.
    /// ANSI: 0x2B comma, 0x2F period, 0x2C slash.
    public static let punctuationKeycodes: Set<UInt16> = [0x2B, 0x2F, 0x2C]

    public private(set) var strokes: [KeyStroke] = []
    public var layoutID: String = ""

    public var count: Int { strokes.count }

    public var punctuationMarksCount: Int {
        strokes.filter { Self.punctuationKeycodes.contains($0.keycode) }.count
    }

    public var beginsWithPunctuation: Bool {
        strokes.first.map { Self.punctuationKeycodes.contains($0.keycode) } ?? false
    }

    public init() {}

    public mutating func append(_ stroke: KeyStroke) {
        strokes.append(stroke)
        if strokes.count > Self.maxLength {
            strokes.removeFirst(strokes.count - Self.maxLength)
        }
    }

    public mutating func removeLast() {
        if !strokes.isEmpty { strokes.removeLast() }
    }

    public mutating func removeAll() {
        strokes.removeAll()
    }
}
