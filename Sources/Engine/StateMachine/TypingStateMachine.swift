public enum EngineEffect: Equatable, Sendable {
    case switchLayout                     // A2: сменить раскладку системно
    case playSound(SoundMask)             // A13
    case deleteCharacters(count: Int)     // стирание слова backspace'ами
    case replayBuffer([KeyStroke])        // заново постить ЭТИ нажатия (после смены раскладки)
    case resetBuffers
    case toggleAutocorrection             // по hotkeyToggleAutocorrection
    case none
}

/// Чистый оркестратор автоконвертации: нажатия → буфер → вердикт LayoutChecker →
/// эффекты, которые App исполняет (смена раскладки, backspace'ы, реплей, звук).
/// Не знает про CGEvent/TIS — весь I/O на стороне App.
public struct TypingStateMachine: Sendable {
    public private(set) var rawBuffer = KeyStrokeBuffer()
    private var undoBuffer = KeyStrokeBuffer()
    private var settings: AppSettings
    private let engine: ConversionEngine
    private let checker: LayoutChecker
    private var cancelNextWord = false
    public private(set) var autocorrectionIsActive: Bool

    public init(settings: AppSettings, engine: ConversionEngine, checker: LayoutChecker) {
        self.settings = settings
        self.engine = engine
        self.checker = checker
        self.autocorrectionIsActive = settings.isAutocorrectionActive
    }

    public mutating func handleKeyDown(_ key: KeyStroke, isSeparator: Bool,
                                       currentLayoutIsRussian: Bool) -> [EngineEffect] {
        if key.keycode == 0x35 { return reset() }                    // Escape
        if key.keycode == 0x33 {                                     // Backspace
            rawBuffer.removeLast()
            undoBuffer.removeLast()
            return [.none]
        }
        guard autocorrectionIsActive else { return [.none] }
        if isSeparator {
            return tryAutoconvert(currentLayoutIsRussian: currentLayoutIsRussian)
        }
        rawBuffer.append(key)
        undoBuffer.append(key)
        return [.none]
    }

    public mutating func handleManualLayoutSwitch() -> [EngineEffect] {
        if settings.cancelNextWordAfterManualSwitch { cancelNextWord = true }
        return [.switchLayout, .playSound(.switchToEnglish)] // направление звука уточняет App
    }

    public mutating func handleEscape() -> [EngineEffect] { reset() }

    public mutating func handleBackspace() -> [EngineEffect] {
        rawBuffer.removeLast()
        return [.none]
    }

    public mutating func handleUndoHotkey() -> [EngineEffect] {
        guard undoBuffer.count > 0 else { return [.none] }
        let strokes = undoBuffer.strokes
        undoBuffer.removeAll()
        return [.switchLayout, .deleteCharacters(count: strokes.count),
                .replayBuffer(strokes), .playSound(.undo)]
    }

    public mutating func toggleAutocorrection() -> [EngineEffect] {
        autocorrectionIsActive.toggle()
        return [.toggleAutocorrection]
    }

    private mutating func tryAutoconvert(currentLayoutIsRussian: Bool) -> [EngineEffect] {
        defer { rawBuffer.removeAll() }
        guard rawBuffer.count > 0 else { return [.none] }
        if cancelNextWord {
            cancelNextWord = false
            undoBuffer.removeAll()
            return [.resetBuffers]
        }
        // C1: русское слово в русской раскладке корректно — не конвертируем
        // и не кладём в undoBuffer (откатывать нечего).
        if currentLayoutIsRussian {
            undoBuffer.removeAll()
            return [.resetBuffers]
        }
        // A3: буфер виртуально «переключается» в целевую раскладку перед проверкой.
        // MVP проверяет только направление «набирали EN, имели в виду RU»
        // (checker вызывается с isEnglishLayout: true), поэтому интерпретируем
        // keycode'ы через русскую таблицу.
        rawBuffer.layoutID = settings.russianLayoutID
        let word = rawBuffer.stringValue(convertingWith: engine)
        let verdict = checker.check(word, isEnglishLayout: true)
        switch verdict {
        case .incorrectLayout:
            let strokes = rawBuffer.strokes
            // I1: undo хранит только последнее сконвертированное слово
            undoBuffer.removeAll()
            for s in strokes { undoBuffer.append(s) }
            return [.switchLayout, .deleteCharacters(count: strokes.count),
                    .replayBuffer(strokes), .playSound(.autoConvert), .resetBuffers]
        case .unknown, .exception:
            undoBuffer.removeAll()
            return [.resetBuffers]
        }
    }

    private mutating func reset() -> [EngineEffect] {
        rawBuffer.removeAll()
        undoBuffer.removeAll()
        return [.resetBuffers]
    }
}
