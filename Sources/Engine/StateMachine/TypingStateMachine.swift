public enum EngineEffect: Equatable, Sendable {
    case switchLayout                     // A2: сменить раскладку системно
    case playSound(SoundMask)             // A13
    case deleteCharacters(count: Int)     // стирание слова backspace'ами
    case replayBuffer([KeyStroke], word: String) // strokes — keycode-реплей после подтверждённой смены раскладки; word — fallback для unicode-постинга
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
    /// A3-toggle: автоотключение автоконвертации по сепараторам.
    /// Когда false, буфер последнего слова продолжает копиться — он нужен
    /// для ручной конвертации (handleManualConvert).
    public private(set) var autoConvertEnabled: Bool

    public init(settings: AppSettings, engine: ConversionEngine, checker: LayoutChecker) {
        self.settings = settings
        self.engine = engine
        self.checker = checker
        self.autocorrectionIsActive = settings.isAutocorrectionActive
        self.autoConvertEnabled = settings.autoConvertEnabled
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
        // фантомные/сервисные keycode'ы (AltGr и пр.) не печатают символов —
        // в буфер не попадают, иначе съедут deleteCharacters/replayBuffer.
        guard engine.isCharacterKey(key.keycode) else { return [.none] }
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
        // word = исходный набранный текст: strokes читаются через таблицу раскладки,
        // в которой слово было набрано (layoutID ставят заполнители буфера). Пустой
        // layoutID — legacy-путь авто-конвертации: она всегда EN→RU, читаем через
        // английскую таблицу (иначе undo — визуальный no-op).
        if undoBuffer.layoutID.isEmpty {
            undoBuffer.layoutID = settings.englishLayoutID
        }
        let word = undoBuffer.stringValue(convertingWith: engine)
        undoBuffer.removeAll()
        return [.switchLayout, .deleteCharacters(count: strokes.count),
                .replayBuffer(strokes, word: word), .playSound(.undo)]
    }

    public mutating func toggleAutocorrection() -> [EngineEffect] {
        autocorrectionIsActive.toggle()
        return [.toggleAutocorrection]
    }

    public mutating func setAutoConvertEnabled(_ on: Bool) {
        autoConvertEnabled = on
    }

    /// A2-manual: принудительная конвертация последнего слова (ручная, как в Punto):
    /// без словаря, всегда переводит, меняет раскладку и перепечатывает слово.
    /// Каноничное поведение Punto: повторное нажатие сразу после конвертации
    /// (rawBuffer уже пуст) откатывает её через undoBuffer.
    public mutating func handleManualConvert(currentLayoutIsRussian: Bool) -> [EngineEffect] {
        if rawBuffer.count == 0 {
            guard undoBuffer.count > 0 else { return [.none] }
            return handleUndoHotkey()
        }
        defer { rawBuffer.removeAll() }
        let strokes = rawBuffer.strokes
        // Исходный текст читался в ТЕКУЩЕЙ раскладке; целевое слово — интерпретация
        // тех же keycode'ов через таблицу противоположной раскладки.
        rawBuffer.layoutID = currentLayoutIsRussian ? settings.englishLayoutID : settings.russianLayoutID
        let word = rawBuffer.stringValue(convertingWith: engine)
        undoBuffer.removeAll()
        for s in strokes { undoBuffer.append(s) }
        undoBuffer.layoutID = currentLayoutIsRussian ? settings.russianLayoutID : settings.englishLayoutID
        return [.switchLayout, .deleteCharacters(count: strokes.count),
                .replayBuffer(strokes, word: word), .playSound(.autoConvert), .resetBuffers]
    }

    private mutating func tryAutoconvert(currentLayoutIsRussian: Bool) -> [EngineEffect] {
        defer { rawBuffer.removeAll() }
        guard rawBuffer.count > 0 else { return [.none] }
        // Флаг отмены потребляем сепаратором в любом состоянии: если он переживёт
        // период выключенной авто-конвертации, следующее слово молча не сконвертируется.
        if cancelNextWord {
            cancelNextWord = false
            undoBuffer.removeAll()
            return [.resetBuffers]
        }
        guard autoConvertEnabled else { undoBuffer.removeAll(); return [.resetBuffers] }
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
            // strokes набраны в EN-раскладке — undo читает их через английскую таблицу
            undoBuffer.layoutID = settings.englishLayoutID
            return [.switchLayout, .deleteCharacters(count: strokes.count),
                    .replayBuffer(strokes, word: word), .playSound(.autoConvert), .resetBuffers]
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
