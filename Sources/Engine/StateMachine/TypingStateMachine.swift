public enum EngineEffect: Equatable, Sendable {
    case switchLayout                     // A2: сменить раскладку системно
    case playSound(SoundMask)             // A13
    case deleteCharacters(count: Int)     // стирание слова backspace'ами
    case replayText(word: String, layoutID: String) // посимвольный keycode-реплей результата в целевой раскладке
    case resetBuffers
    case toggleAutocorrection             // по hotkeyToggleAutocorrection
    case none
}

/// Чистый оркестратор автоконвертации: нажатия → буфер → вердикт LayoutChecker →
/// эффекты, которые App исполняет (смена раскладки, backspace'ы, реплей, звук).
/// Не знает про CGEvent/TIS — весь I/O на стороне App.
public struct TypingStateMachine: Sendable {
    public private(set) var rawBuffer = KeyStrokeBuffer()
    /// Пара переключения (UC-3): текущий текст в документе и тот, что вернёт
    /// следующее нажатие. Swap, не clear — цикл «туда-обратно» бесконечен.
    private var toggleCurrent: (text: String, layoutID: String)?
    private var toggleOther: (text: String, layoutID: String)?
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
            return [.none]
        }
        guard autocorrectionIsActive else { return [.none] }
        if isSeparator {
            return tryAutoconvert(currentLayoutIsRussian: currentLayoutIsRussian)
        }
        // фантомные/сервисные keycode'ы (AltGr и пр.) не печатают символов —
        // в буфер не попадают, иначе съедут deleteCharacters/replayText.
        guard engine.isCharacterKey(key.keycode) else { return [.none] }
        rawBuffer.append(key)
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

    /// Классическая одноразовая отмена: вернуть исходный текст пары и забыть
    /// её (в отличие от handleManualConvert, который СВОПАЕТ пару и крутит
    /// цикл дальше). В продукте не вызывается (UC-2 п.5) — публичный API
    /// для тестов и внешних интеграций.
    public mutating func handleUndoHotkey() -> [EngineEffect] {
        guard let current = toggleCurrent, let other = toggleOther else { return [.none] }
        toggleCurrent = nil
        toggleOther = nil
        return [.switchLayout, .deleteCharacters(count: current.text.count),
                .replayText(word: other.text, layoutID: other.layoutID), .playSound(.undo)]
    }

    public mutating func toggleAutocorrection() -> [EngineEffect] {
        autocorrectionIsActive.toggle()
        return [.toggleAutocorrection]
    }

    public mutating func setAutoConvertEnabled(_ on: Bool) {
        autoConvertEnabled = on
    }

    /// Сброс буферов набора без эффектов. Нужен, когда selection-путь отработал
    /// при непустом rawBuffer: корреспонденция «keystrokes ↔ текст в поле»
    /// разорвана (мышь/вставка), хранить штрихи дальше небезопасно — на
    /// сепараторе deleteCharacters перестёр бы чужой текст. Пара переключения
    /// тоже сбрасывается (I4).
    public mutating func discardTypingBuffers() {
        rawBuffer.removeAll()
        toggleCurrent = nil
        toggleOther = nil
    }

    /// A2-manual: принудительная конвертация последнего слова (ручная, как в Punto):
    /// без словаря, всегда переводит, меняет раскладку и перепечатывает слово.
    /// Буфер пуст + пара есть → swap пары (UC-3): бесконечное туда-обратно.
    public mutating func handleManualConvert(currentLayoutIsRussian: Bool,
                                             selectionExists: Bool = false) -> [EngineEffect] {
        if rawBuffer.count == 0 {
            // Активное выделение имеет приоритет над откатом: deleteCharacters шлёт
            // backspace'ы, а backspace с выделением съедает выделение целиком + текст
            // перед ним — деструктивный откат. App с selectionExists: true уйдёт в
            // конвертацию выделения и сюда больше не вернётся.
            if selectionExists { return [.none] }  // App уйдёт в конвертацию выделения
            guard let current = toggleCurrent, let other = toggleOther else { return [.none] }
            toggleCurrent = other
            toggleOther = current
            return [.switchLayout, .deleteCharacters(count: current.text.count),
                    .replayText(word: other.text, layoutID: other.layoutID), .playSound(.undo)]
        }
        defer { rawBuffer.removeAll() }
        // I10: слово длиннее буфера не конвертируем — typed-строка неполная,
        // deleteCharacters по ней стёр бы больше, чем вставим (нарушение I2).
        guard !rawBuffer.overflowed else { return [.none] }
        // Исходный текст = буфер, прочитанный через таблицу ТЕКУЩЕЙ раскладки
        // (то, что видел пользователь). Целевое слово — конвертация этого текста.
        rawBuffer.layoutID = currentLayoutIsRussian ? settings.russianLayoutID : settings.englishLayoutID
        let typed = rawBuffer.stringValue(convertingWith: engine)
        let mode: ConversionMode = currentLayoutIsRussian ? .toEnglish : .toRussian
        let converted = engine.convert(typed, mode: mode)
        let sourceLayoutID = currentLayoutIsRussian ? settings.russianLayoutID : settings.englishLayoutID
        let targetLayoutID = currentLayoutIsRussian ? settings.englishLayoutID : settings.russianLayoutID
        // UC-3: пара переключения := (текущий: converted + целевая; другой: typed + исходная)
        toggleCurrent = (converted, targetLayoutID)
        toggleOther = (typed, sourceLayoutID)
        return [.switchLayout, .deleteCharacters(count: typed.count),
                .replayText(word: converted, layoutID: targetLayoutID),
                .playSound(.autoConvert), .resetBuffers]
    }

    private mutating func tryAutoconvert(currentLayoutIsRussian: Bool) -> [EngineEffect] {
        defer { rawBuffer.removeAll() }
        guard rawBuffer.count > 0 else { return [.none] }
        // I10 (UC-1b): переполненный буфер → не конвертируем, буферы сброшены.
        guard !rawBuffer.overflowed else { return reset() }
        // Флаг отмены потребляем сепаратором в любом состоянии: если он переживёт
        // период выключенной авто-конвертации, следующее слово молча не сконвертируется.
        if cancelNextWord {
            cancelNextWord = false
            toggleCurrent = nil
            toggleOther = nil
            return [.resetBuffers]
        }
        guard autoConvertEnabled else { toggleCurrent = nil; toggleOther = nil; return [.resetBuffers] }
        // C1: русское слово в русской раскладке корректно — не конвертируем
        // и не кладём пару (переключать нечего).
        if currentLayoutIsRussian {
            toggleCurrent = nil
            toggleOther = nil
            return [.resetBuffers]
        }
        // A3: буфер читаем через таблицу ТЕКУЩЕЙ (EN) раскладки — typed = то, что
        // видел пользователь. Проверка по словарю идёт по ядру этого текста
        // (LayoutChecker обрезает не-буквы), конвертация — того же текста
        // посимвольно (пунктуация конвертируется тождественно).
        rawBuffer.layoutID = settings.englishLayoutID
        let typed = rawBuffer.stringValue(convertingWith: engine)
        let verdict = checker.check(typed, isEnglishLayout: true)
        switch verdict {
        case .incorrectLayout:
            let converted = engine.convert(typed, mode: .toRussian)
            // UC-3: пара переключения := (текущий: converted + RU; другой: typed + EN)
            toggleCurrent = (converted, settings.russianLayoutID)
            toggleOther = (typed, settings.englishLayoutID)
            return [.switchLayout, .deleteCharacters(count: typed.count),
                    .replayText(word: converted, layoutID: settings.russianLayoutID),
                    .playSound(.autoConvert), .resetBuffers]
        case .unknown, .exception:
            toggleCurrent = nil
            toggleOther = nil
            return [.resetBuffers]
        }
    }

    private mutating func reset() -> [EngineEffect] {
        rawBuffer.removeAll()
        toggleCurrent = nil
        toggleOther = nil
        return [.resetBuffers]
    }
}
