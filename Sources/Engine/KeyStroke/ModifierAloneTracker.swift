/// Отслеживает «модификатор нажат и отпущен без других клавиш».
/// keycode модификаторов передаётся снаружи (App знает раскладко-независимые коды).
public struct ModifierAloneTracker: Sendable {
    public enum KeyPhase: Sendable { case down, up }

    private var pressed: Set<UInt16> = []
    private var alone = false

    public init() {}

    /// isTrackedModifier: входит ли клавиша в отслеживаемый набор модификаторов.
    /// Возвращает true РОВНО ОДИН раз — на отпускании последнего зажатого
    /// модификатора, если с момента первого его нажатия не было других клавиш
    /// (повторные keyDown от автоповтора — не «другая клавиша», повторный
    /// insert идемпотентен; отпускание посторонней клавиши флаг не трогает —
    /// сбрасывает только её нажатие).
    public mutating func handle(keycode: UInt16, phase: KeyPhase,
                                isTrackedModifier: (UInt16) -> Bool) -> Bool {
        switch (phase, isTrackedModifier(keycode)) {
        case (.down, true):
            if pressed.isEmpty { alone = true }
            pressed.insert(keycode)
            return false
        case (.down, false):
            if !pressed.isEmpty { alone = false }
            return false
        case (.up, true):
            pressed.remove(keycode)
            guard pressed.isEmpty else { return false }
            defer { alone = false }
            return alone
        case (.up, false):
            return false
        }
    }
}
