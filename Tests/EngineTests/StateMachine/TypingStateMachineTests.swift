import Testing
@testable import Engine

struct TypingStateMachineTests {
    let ruLayoutID = AppSettings.default.russianLayoutID
    let enLayoutID = AppSettings.default.englishLayoutID

    /// Фикстура: keycode'ы 0x0C/0x2B/0x2F/0x1E/0x27 читаются через EN как "dbogl",
    /// через RU как "вборд"; пары симметричны (как в реальных keycode-таблицах).
    /// Триггеры — в «как напечатано» форме: typed-текст читается через таблицу
    /// текущей раскладки, поэтому EN-набор проверяется по EN-триггеру "dbogl".
    func makeSM(triggers: [String] = ["dbogl"], autocorrection: Bool = true,
                cancelAfterManualSwitch: Bool = false) -> TypingStateMachine {
        var s = AppSettings.default
        s.isAutocorrectionActive = autocorrection
        s.cancelNextWordAfterManualSwitch = cancelAfterManualSwitch
        let engine = ConversionEngine(
            russianToEnglish: CharacterPairMap(pairs: ["в":"d","б":"b","о":"o","р":"g","д":"l"]),
            englishToRussian: CharacterPairMap(pairs: ["d":"в","b":"б","o":"о","g":"р","l":"д"]),
            keycodeToCharRU: [0x0C:"в", 0x2F:"о", 0x2B:"б", 0x1E:"р", 0x27:"д"],
            keycodeToCharEN: [0x0C:"d", 0x2F:"o", 0x2B:"b", 0x1E:"g", 0x27:"l"])
        return TypingStateMachine(settings: s, engine: engine,
                                  checker: LayoutChecker(triggers: triggers, userRules: []))
    }

    /// Фикстура с реальными ANSI-позициями: «ghbdtn» на 0x05/0x04/0x0B/0x02/0x10/0x2D
    /// и клавиша '.' на 0x2F (в RU-раскладке той же клавишей печатается «ю»).
    /// Пары включают тождественную '.'↔'.' — как оверлей AppController.
    func makeSMPunctuation(triggers: [String] = ["ghbdtn"]) -> TypingStateMachine {
        let s = AppSettings.default
        let engine = ConversionEngine(
            russianToEnglish: CharacterPairMap(pairs: ["п":"g","р":"h","и":"b","в":"d","е":"t","т":"n",".":"."]),
            englishToRussian: CharacterPairMap(pairs: ["g":"п","h":"р","b":"и","d":"в","t":"е","n":"т",".":"."]),
            keycodeToCharRU: [0x05:"п", 0x04:"р", 0x0B:"и", 0x02:"в", 0x10:"е", 0x2D:"т", 0x2F:"ю"],
            keycodeToCharEN: [0x05:"g", 0x04:"h", 0x0B:"b", 0x02:"d", 0x10:"t", 0x2D:"n", 0x2F:"."])
        return TypingStateMachine(settings: s, engine: engine,
                                  checker: LayoutChecker(triggers: triggers, userRules: []))
    }

    /// Фикстура D8: та же раскладка, что у makeSM, плюс shift-слой для
    /// 0x0C ('d'/'в') и 0x27 ('l'/'д') — регистр читается из флага штриха.
    func makeSMCase(triggers: [String] = ["zzzzz"]) -> TypingStateMachine {
        let s = AppSettings.default
        let engine = ConversionEngine(
            russianToEnglish: CharacterPairMap(pairs: ["в":"d","б":"b","о":"o","р":"g","д":"l"]),
            englishToRussian: CharacterPairMap(pairs: ["d":"в","b":"б","o":"о","g":"р","l":"д"]),
            keycodeToCharRU: [0x0C:"в", 0x2F:"о", 0x2B:"б", 0x1E:"р", 0x27:"д"],
            keycodeToCharEN: [0x0C:"d", 0x2F:"o", 0x2B:"b", 0x1E:"g", 0x27:"l"],
            keycodeToCharShiftRU: [0x0C:"В", 0x27:"Д"],
            keycodeToCharShiftEN: [0x0C:"D", 0x27:"L"])
        return TypingStateMachine(settings: s, engine: engine,
                                  checker: LayoutChecker(triggers: triggers, userRules: []))
    }

    /// Набор слова "dbogl" (keycode'ы фикстуры) в EN-раскладке.
    func typeDbogl(_ sm: inout TypingStateMachine, layoutIsRussian: Bool = false) {
        for k: UInt16 in [0x0C, 0x2B, 0x2F, 0x1E, 0x27] {
            _ = sm.handleKeyDown(KeyStroke(keycode: k, modifiers: 0), isSeparator: false,
                                 currentLayoutIsRussian: layoutIsRussian)
        }
    }

    @Test func plainTypingAccumulatesInBuffer() {
        var sm = makeSM()
        let e = sm.handleKeyDown(KeyStroke(keycode: 0x0C, modifiers: 0), isSeparator: false, currentLayoutIsRussian: false)
        #expect(e == [.none])
        #expect(sm.rawBuffer.count == 1)
    }

    @Test func separatorAfterTriggerWordConverts() {
        var sm = makeSM()
        // набираем "dbogl" (typed читается через EN-таблицу), триггер "dbogl"
        typeDbogl(&sm)
        let effects = sm.handleKeyDown(KeyStroke(keycode: 0x31, modifiers: 0), isSeparator: true, currentLayoutIsRussian: false)
        #expect(effects.contains(.switchLayout))
        #expect(effects.contains(.deleteCharacters(count: 5)))
        #expect(effects.contains { if case .replayText(let w, let l) = $0 {
            return w == "вборд" && l == ruLayoutID } else { return false } })
        #expect(effects.contains(.playSound(.autoConvert)))
        #expect(sm.rawBuffer.count == 0)
    }

    @Test func separatorAfterPunctuationEndedWordConvertsWholeWord() {
        // Регрессия «предложение»: клавиша '.' (0x2F) слово не рвёт — в буфере
        // «ghbdtn.», конвертируется целиком, '.' → '.' тождественно.
        var sm = makeSMPunctuation()
        for k: UInt16 in [0x05, 0x04, 0x0B, 0x02, 0x10, 0x2D, 0x2F] {
            _ = sm.handleKeyDown(KeyStroke(keycode: k, modifiers: 0), isSeparator: false, currentLayoutIsRussian: false)
        }
        let effects = sm.handleKeyDown(KeyStroke(keycode: 0x31, modifiers: 0), isSeparator: true, currentLayoutIsRussian: false)
        #expect(effects.contains(.switchLayout))
        #expect(effects.contains(.deleteCharacters(count: 7)))
        #expect(effects.contains { if case .replayText(let w, let l) = $0 {
            return w == "привет." && l == ruLayoutID } else { return false } })
        #expect(effects.contains(.playSound(.autoConvert)))
        #expect(sm.rawBuffer.count == 0)
    }

    // MARK: - D8: регистр букв сохраняется посимвольно

    @Test func conversionPreservesLetterCase() {
        // D8: «DbogL» (Shift на первой и последней клавишах) → «ВборД»,
        // регистр каждой буквы переносится; deleteCharacters по длине typed (I2).
        var sm = makeSMCase()
        let word: [(UInt16, UInt64)] = [
            (0x0C, 0x20000), (0x2B, 0), (0x2F, 0), (0x1E, 0), (0x27, 0x20000),
        ]
        for (k, m) in word {
            _ = sm.handleKeyDown(KeyStroke(keycode: k, modifiers: m), isSeparator: false,
                                 currentLayoutIsRussian: false)
        }
        let effects = sm.handleManualConvert(currentLayoutIsRussian: false)
        #expect(effects.contains(.switchLayout))
        #expect(effects.contains(.deleteCharacters(count: 5)))
        #expect(effects.contains { if case .replayText(let w, let l) = $0 {
            return w == "ВборД" && l == ruLayoutID } else { return false } })
        // toggle обратно возвращает исходный текст с исходным регистром
        let back = sm.handleManualConvert(currentLayoutIsRussian: false)
        #expect(back.contains(.deleteCharacters(count: 5)))
        #expect(back.contains { if case .replayText(let w, let l) = $0 {
            return w == "DbogL" && l == enLayoutID } else { return false } })
    }

    @Test func autoConversionPreservesLetterCase() {
        // D8 на auto-пути: то же слово, конвертация по сепаратору.
        var sm = makeSMCase(triggers: ["dbogl"])
        let word: [(UInt16, UInt64)] = [
            (0x0C, 0x20000), (0x2B, 0), (0x2F, 0), (0x1E, 0), (0x27, 0x20000),
        ]
        for (k, m) in word {
            _ = sm.handleKeyDown(KeyStroke(keycode: k, modifiers: m), isSeparator: false,
                                 currentLayoutIsRussian: false)
        }
        let effects = sm.handleKeyDown(KeyStroke(keycode: 0x31, modifiers: 0), isSeparator: true,
                                       currentLayoutIsRussian: false)
        #expect(effects.contains(.deleteCharacters(count: 5)))
        #expect(effects.contains { if case .replayText(let w, let l) = $0 {
            return w == "ВборД" && l == ruLayoutID } else { return false } })
    }

    // MARK: - UC-3: бесконечное переключение (swap пары)

    @Test func toggleCyclesForeverAfterManualConversion() {
        // D18: третье, пятое, десятое нажатие крутят цикл бесконечно.
        var sm = makeSM(triggers: ["zzzzz"])
        typeDbogl(&sm)
        _ = sm.handleManualConvert(currentLayoutIsRussian: false) // "dbogl" → "вборд"
        // откат → оригинал
        let back = sm.handleManualConvert(currentLayoutIsRussian: false)
        #expect(back.contains(.switchLayout))
        #expect(back.contains(.deleteCharacters(count: 5)))
        #expect(back.contains { if case .replayText(let w, let l) = $0 {
            return w == "dbogl" && l == enLayoutID } else { return false } })
        #expect(back.contains(.playSound(.undo)))
        // снова конверт → converted
        let again = sm.handleManualConvert(currentLayoutIsRussian: false)
        #expect(again.contains(.deleteCharacters(count: 5)))
        #expect(again.contains { if case .replayText(let w, let l) = $0 {
            return w == "вборд" && l == ruLayoutID } else { return false } })
        // и снова откат → оригинал (раньше цикл обрывался здесь)
        let again2 = sm.handleManualConvert(currentLayoutIsRussian: false)
        #expect(again2.contains(.deleteCharacters(count: 5)))
        #expect(again2.contains { if case .replayText(let w, let l) = $0 {
            return w == "dbogl" && l == enLayoutID } else { return false } })
        // четвёртый цикл для верности
        let again3 = sm.handleManualConvert(currentLayoutIsRussian: false)
        #expect(again3.contains { if case .replayText(let w, _) = $0 {
            return w == "вборд" } else { return false } })
    }

    @Test func toggleCyclesAfterAutoConversionWithPunctuation() {
        // D18 на auto-пути с пунктуацией: «ghbdtn.» → «привет.» → «ghbdtn.» → …
        var sm = makeSMPunctuation()
        for k: UInt16 in [0x05, 0x04, 0x0B, 0x02, 0x10, 0x2D, 0x2F] {
            _ = sm.handleKeyDown(KeyStroke(keycode: k, modifiers: 0), isSeparator: false, currentLayoutIsRussian: false)
        }
        _ = sm.handleKeyDown(KeyStroke(keycode: 0x31, modifiers: 0), isSeparator: true, currentLayoutIsRussian: false)
        let back = sm.handleManualConvert(currentLayoutIsRussian: false)
        #expect(back.contains(.deleteCharacters(count: 7)))
        #expect(back.contains { if case .replayText(let w, let l) = $0 {
            return w == "ghbdtn." && l == enLayoutID } else { return false } })
        let again = sm.handleManualConvert(currentLayoutIsRussian: false)
        #expect(again.contains(.deleteCharacters(count: 7)))
        #expect(again.contains { if case .replayText(let w, let l) = $0 {
            return w == "привет." && l == ruLayoutID } else { return false } })
    }

    @Test func toggleSurvivesTypingAndBackspaceUntilNextConversion() {
        // UC-3 п.4: печать наполняет буфер заново; пара жива, пока её не
        // перезапишет следующая КОНВЕРТАЦИЯ (набор + стирание — не конвертация).
        var sm = makeSM(triggers: ["zzzzz"])
        typeDbogl(&sm)
        _ = sm.handleManualConvert(currentLayoutIsRussian: false) // "dbogl" → "вборд"
        _ = sm.handleKeyDown(KeyStroke(keycode: 0x0C, modifiers: 0), isSeparator: false, currentLayoutIsRussian: false)
        #expect(sm.rawBuffer.count == 1)
        _ = sm.handleKeyDown(KeyStroke(keycode: 0x33, modifiers: 0), isSeparator: false, currentLayoutIsRussian: false)
        #expect(sm.rawBuffer.count == 0)
        let toggle = sm.handleManualConvert(currentLayoutIsRussian: false)
        #expect(toggle.contains { if case .replayText(let w, _) = $0 {
            return w == "dbogl" } else { return false } })
    }

    @Test func escapeClearsTogglePair() {
        // UC-1 п.1: Escape сбрасывает буфер набора И пару переключения.
        var sm = makeSM(triggers: ["zzzzz"])
        typeDbogl(&sm)
        _ = sm.handleManualConvert(currentLayoutIsRussian: false) // "dbogl" → "вборд"
        let e = sm.handleKeyDown(KeyStroke(keycode: 0x35, modifiers: 0), isSeparator: false, currentLayoutIsRussian: false)
        #expect(e == [.resetBuffers])
        #expect(sm.handleManualConvert(currentLayoutIsRussian: false) == [.none])
    }

    @Test func discardTypingBuffersClearsTogglePair() {
        // I4: selection-путь сбрасывает и буфер, и пару.
        var sm = makeSM(triggers: ["zzzzz"])
        typeDbogl(&sm)
        _ = sm.handleManualConvert(currentLayoutIsRussian: false) // "dbogl" → "вборд"
        sm.discardTypingBuffers()
        #expect(sm.handleManualConvert(currentLayoutIsRussian: false) == [.none])
    }

    // MARK: - Одноразовая отмена (handleUndoHotkey: вернуть исходное и забыть)

    @Test func undoHotkeyReturnsOriginalAndClearsPair() {
        var sm = makeSM()
        typeDbogl(&sm)
        _ = sm.handleKeyDown(KeyStroke(keycode: 0x31, modifiers: 0), isSeparator: true, currentLayoutIsRussian: false) // конвертация
        let e = sm.handleUndoHotkey()
        #expect(e.contains(.switchLayout))
        #expect(e.contains(.deleteCharacters(count: 5)))
        #expect(e.contains { if case .replayText(let w, let l) = $0 {
            return w == "dbogl" && l == enLayoutID } else { return false } })
        #expect(e.contains(.playSound(.undo)))
        // пара очищена — классическая отмена не крутит цикл (в отличие от UC-3)
        #expect(sm.handleManualConvert(currentLayoutIsRussian: false) == [.none])
    }

    @Test func undoAfterManualConvertRUtoENRestoresRussian() {
        var sm = makeSM()
        typeDbogl(&sm, layoutIsRussian: true)
        _ = sm.handleManualConvert(currentLayoutIsRussian: true) // "вборд" → "dbogl"
        let undo = sm.handleUndoHotkey()
        #expect(undo.contains(.switchLayout))
        // undo восстанавливает исходный набранный текст (русское слово)
        #expect(undo.contains { if case .replayText(let w, let l) = $0 {
            return w == "вборд" && l == ruLayoutID } else { return false } })
        #expect(undo.contains(.playSound(.undo)))
    }

    @Test func undoAfterPunctuationConversionRestoresOriginalWord() {
        var sm = makeSMPunctuation()
        for k: UInt16 in [0x05, 0x04, 0x0B, 0x02, 0x10, 0x2D, 0x2F] {
            _ = sm.handleKeyDown(KeyStroke(keycode: k, modifiers: 0), isSeparator: false, currentLayoutIsRussian: false)
        }
        _ = sm.handleKeyDown(KeyStroke(keycode: 0x31, modifiers: 0), isSeparator: true, currentLayoutIsRussian: false)
        let undo = sm.handleUndoHotkey()
        #expect(undo.contains(.switchLayout))
        #expect(undo.contains(.deleteCharacters(count: 7)))
        #expect(undo.contains { if case .replayText(let w, let l) = $0 {
            return w == "ghbdtn." && l == enLayoutID } else { return false } })
        #expect(undo.contains(.playSound(.undo)))
    }

    @Test func undoCoversOnlyLastConvertedWord() {
        var sm = makeSM()
        // слово1 "oo" — не триггер, пары после него нет
        _ = sm.handleKeyDown(KeyStroke(keycode: 0x2F, modifiers: 0), isSeparator: false, currentLayoutIsRussian: false)
        _ = sm.handleKeyDown(KeyStroke(keycode: 0x2F, modifiers: 0), isSeparator: false, currentLayoutIsRussian: false)
        _ = sm.handleKeyDown(KeyStroke(keycode: 0x31, modifiers: 0), isSeparator: true, currentLayoutIsRussian: false)
        // слово2 "dbogl" — конвертируется
        typeDbogl(&sm)
        _ = sm.handleKeyDown(KeyStroke(keycode: 0x31, modifiers: 0), isSeparator: true, currentLayoutIsRussian: false)
        let e = sm.handleUndoHotkey()
        // undo стирает и реплеит только последнее сконвертированное слово (5), не слово1+слово2 (7)
        #expect(e.contains(.deleteCharacters(count: 5)))
        #expect(e.contains { if case .replayText(let w, _) = $0 {
            return w == "dbogl" } else { return false } })
    }

    // MARK: - Остальные сценарии

    @Test func separatorAfterUnknownWordJustResets() {
        var sm = makeSM(triggers: ["zzzzz"])
        _ = sm.handleKeyDown(KeyStroke(keycode: 0x0C, modifiers: 0), isSeparator: false, currentLayoutIsRussian: false)
        let effects = sm.handleKeyDown(KeyStroke(keycode: 0x31, modifiers: 0), isSeparator: true, currentLayoutIsRussian: false)
        #expect(effects == [.resetBuffers])
        #expect(sm.rawBuffer.count == 0)
    }

    @Test func escapeResetsBuffers() {
        var sm = makeSM()
        _ = sm.handleKeyDown(KeyStroke(keycode: 0x0C, modifiers: 0), isSeparator: false, currentLayoutIsRussian: false)
        let e = sm.handleKeyDown(KeyStroke(keycode: 0x35, modifiers: 0), isSeparator: false, currentLayoutIsRussian: false)
        #expect(e == [.resetBuffers])
        #expect(sm.rawBuffer.count == 0)
    }

    @Test func backspaceRemovesLastStroke() {
        var sm = makeSM()
        _ = sm.handleKeyDown(KeyStroke(keycode: 0x0C, modifiers: 0), isSeparator: false, currentLayoutIsRussian: false)
        _ = sm.handleKeyDown(KeyStroke(keycode: 0x33, modifiers: 0), isSeparator: false, currentLayoutIsRussian: false)
        #expect(sm.rawBuffer.count == 0)
    }

    @Test func autocorrectionOffOnlyResets() {
        var sm = makeSM(autocorrection: false)
        _ = sm.handleKeyDown(KeyStroke(keycode: 0x0C, modifiers: 0), isSeparator: false, currentLayoutIsRussian: false)
        #expect(sm.rawBuffer.count == 0)
    }

    @Test func manualSwitchSetsCancelFlag() {
        var sm = makeSM(cancelAfterManualSwitch: true)
        _ = sm.handleManualLayoutSwitch()
        // после ручного переключения следующее слово не конвертируется
        typeDbogl(&sm)
        let effects = sm.handleKeyDown(KeyStroke(keycode: 0x31, modifiers: 0), isSeparator: true, currentLayoutIsRussian: false)
        #expect(!effects.contains(.switchLayout))
    }

    @Test func russianLayoutWordIsNotConverted() {
        var sm = makeSM()
        typeDbogl(&sm, layoutIsRussian: true)
        let effects = sm.handleKeyDown(KeyStroke(keycode: 0x31, modifiers: 0), isSeparator: true, currentLayoutIsRussian: true)
        #expect(effects == [.resetBuffers])
        #expect(!effects.contains(.switchLayout))
        // корректное русское слово не должно быть откатываемо
        let undo = sm.handleManualConvert(currentLayoutIsRussian: true)
        #expect(undo == [.none])
    }

    @Test func phantomUnmappedKeycodeIsIgnored() {
        var sm = makeSM()
        let e = sm.handleKeyDown(KeyStroke(keycode: 179, modifiers: 0), isSeparator: false, currentLayoutIsRussian: false)
        #expect(e == [.none])
        #expect(sm.rawBuffer.count == 0)
    }

    @Test func phantomKeycodeDoesNotShiftConversion() {
        var sm = makeSM()
        // "dbogl" + фантомный keycode 179 посередине: конвертация стирает/реплеит 5 нажатий
        _ = sm.handleKeyDown(KeyStroke(keycode: 0x0C, modifiers: 0), isSeparator: false, currentLayoutIsRussian: false)
        _ = sm.handleKeyDown(KeyStroke(keycode: 179, modifiers: 0), isSeparator: false, currentLayoutIsRussian: false)
        for k: UInt16 in [0x2B, 0x2F, 0x1E, 0x27] {
            _ = sm.handleKeyDown(KeyStroke(keycode: k, modifiers: 0), isSeparator: false, currentLayoutIsRussian: false)
        }
        let effects = sm.handleKeyDown(KeyStroke(keycode: 0x31, modifiers: 0), isSeparator: true, currentLayoutIsRussian: false)
        #expect(effects.contains(.switchLayout))
        #expect(effects.contains(.deleteCharacters(count: 5)))
        #expect(effects.contains { if case .replayText(let w, _) = $0 {
            return w == "вборд" } else { return false } })
    }

    @Test func autoConvertDisabledSkipsConversionButKeepsBuffering() {
        var sm = makeSM()
        sm.setAutoConvertEnabled(false)
        typeDbogl(&sm)
        // буфер последнего слова копится — нужен для ручной конвертации
        #expect(sm.rawBuffer.count == 5)
        let effects = sm.handleKeyDown(KeyStroke(keycode: 0x31, modifiers: 0), isSeparator: true, currentLayoutIsRussian: false)
        #expect(effects == [.resetBuffers])
        #expect(!effects.contains(.switchLayout))
        #expect(!effects.contains { if case .replayText = $0 { return true } else { return false } })
        #expect(sm.rawBuffer.count == 0)
    }

    @Test func autoConvertReenabledConvertsAgain() {
        var sm = makeSM()
        sm.setAutoConvertEnabled(false)
        typeDbogl(&sm)
        _ = sm.handleKeyDown(KeyStroke(keycode: 0x31, modifiers: 0), isSeparator: true, currentLayoutIsRussian: false)
        sm.setAutoConvertEnabled(true)
        typeDbogl(&sm)
        let effects = sm.handleKeyDown(KeyStroke(keycode: 0x31, modifiers: 0), isSeparator: true, currentLayoutIsRussian: false)
        #expect(effects.contains(.switchLayout))
        #expect(effects.contains(.deleteCharacters(count: 5)))
        #expect(effects.contains(.playSound(.autoConvert)))
    }

    @Test func manualConvertENtoRUForcesWithoutDictionary() {
        // триггеры НЕ совпадают — ручная конвертация не смотрит словарь
        var sm = makeSM(triggers: ["zzzzz"])
        typeDbogl(&sm)
        let effects = sm.handleManualConvert(currentLayoutIsRussian: false)
        #expect(effects.contains(.switchLayout))
        #expect(effects.contains(.deleteCharacters(count: 5)))
        #expect(effects.contains { if case .replayText(let w, let l) = $0 {
            return w == "вборд" && l == ruLayoutID } else { return false } })
        #expect(effects.contains(.playSound(.autoConvert)))
        #expect(sm.rawBuffer.count == 0)
    }

    @Test func manualConvertRUtoEN() {
        var sm = makeSM(triggers: ["zzzzz"])
        typeDbogl(&sm, layoutIsRussian: true)
        let effects = sm.handleManualConvert(currentLayoutIsRussian: true)
        #expect(effects.contains(.switchLayout))
        #expect(effects.contains(.deleteCharacters(count: 5)))
        #expect(effects.contains { if case .replayText(let w, let l) = $0 {
            return w == "dbogl" && l == enLayoutID } else { return false } })
        #expect(effects.contains(.playSound(.autoConvert)))
    }

    @Test func manualConvertWithEmptyBuffersDoesNothing() {
        var sm = makeSM()
        #expect(sm.handleManualConvert(currentLayoutIsRussian: false) == [.none])
    }

    @Test func manualConvertWithSelectionSkipsToggle() {
        // активное выделение имеет приоритет над откатом слова (backspace по
        // выделению деструктивен) — engine возвращает [.none], App уйдёт
        // в конвертацию выделения; пара при этом не трогается
        var sm = makeSM(triggers: ["zzzzz"])
        typeDbogl(&sm)
        _ = sm.handleManualConvert(currentLayoutIsRussian: false) // "dbogl" → "вборд", пара непуста
        let effects = sm.handleManualConvert(currentLayoutIsRussian: false, selectionExists: true)
        #expect(effects == [.none])
        let toggle = sm.handleManualConvert(currentLayoutIsRussian: false)
        #expect(toggle.contains { if case .replayText(let w, _) = $0 {
            return w == "dbogl" } else { return false } })
    }

    @Test func manualConvertWithoutSelectionToggles() {
        // регрессия: без выделения повторный хоткей откатывает слово как раньше
        var sm = makeSM(triggers: ["zzzzz"])
        typeDbogl(&sm)
        _ = sm.handleManualConvert(currentLayoutIsRussian: false) // "dbogl" → "вборд"
        let toggleBack = sm.handleManualConvert(currentLayoutIsRussian: false, selectionExists: false)
        #expect(toggleBack.contains(.switchLayout))
        #expect(toggleBack.contains(.deleteCharacters(count: 5)))
        #expect(toggleBack.contains { if case .replayText(let w, _) = $0 {
            return w == "dbogl" } else { return false } })
        #expect(toggleBack.contains(.playSound(.undo)))
    }

    @Test func manualSwitchCancelFlagDrainedWhileAutoConvertDisabled() {
        var sm = makeSM(cancelAfterManualSwitch: true)
        _ = sm.handleManualLayoutSwitch() // cancelNextWord = true
        sm.setAutoConvertEnabled(false)
        // слово, набранное пока авто-конвертация выключена
        typeDbogl(&sm)
        _ = sm.handleKeyDown(KeyStroke(keycode: 0x31, modifiers: 0), isSeparator: true, currentLayoutIsRussian: false)
        sm.setAutoConvertEnabled(true)
        // следующее слово конвертируется — флаг не должен пережить выключенный период
        typeDbogl(&sm)
        let effects = sm.handleKeyDown(KeyStroke(keycode: 0x31, modifiers: 0), isSeparator: true, currentLayoutIsRussian: false)
        #expect(effects.contains(.switchLayout))
        #expect(effects.contains(.deleteCharacters(count: 5)))
        #expect(effects.contains(.playSound(.autoConvert)))
    }

    @Test func discardTypingBuffersPreventsPhantomDelete() {
        // selection-путь при непустом rawBuffer (набрал слово → выделил мышкой):
        // App сбрасывает буферы — иначе после сепаратора фантомный буфер
        // стёр бы чужие символы перед кареткой
        var sm = makeSM()
        typeDbogl(&sm)
        #expect(sm.rawBuffer.count == 5)
        sm.discardTypingBuffers()
        #expect(sm.rawBuffer.count == 0)
        let effects = sm.handleKeyDown(KeyStroke(keycode: 0x31, modifiers: 0), isSeparator: true, currentLayoutIsRussian: false)
        #expect(!effects.contains { if case .deleteCharacters = $0 { return true } else { return false } })
        #expect(effects == [.none])
    }

    // MARK: - I10/D7: переполнение буфера — конвертация запрещена

    @Test func overflowedBufferNeverConvertsOnSeparator() {
        // D7: слово длиннее 32 символов — не конвертируем (typed-строка неполная,
        // deleteCharacters по ней нарушил бы I2), буферы сброшены.
        var sm = makeSM()
        for _ in 0..<33 {
            _ = sm.handleKeyDown(KeyStroke(keycode: 0x0C, modifiers: 0), isSeparator: false, currentLayoutIsRussian: false)
        }
        #expect(sm.rawBuffer.count == 32)
        let effects = sm.handleKeyDown(KeyStroke(keycode: 0x31, modifiers: 0), isSeparator: true, currentLayoutIsRussian: false)
        #expect(effects == [.resetBuffers])
        #expect(!effects.contains(.switchLayout))
        #expect(!effects.contains { if case .deleteCharacters = $0 { return true } else { return false } })
        #expect(!effects.contains { if case .replayText = $0 { return true } else { return false } })
        #expect(sm.rawBuffer.count == 0)
        // пара не создана — переключать нечего
        #expect(sm.handleManualConvert(currentLayoutIsRussian: false) == [.none])
    }

    @Test func overflowedBufferNeverConvertsManually() {
        var sm = makeSM(triggers: ["zzzzz"])
        for _ in 0..<33 {
            _ = sm.handleKeyDown(KeyStroke(keycode: 0x0C, modifiers: 0), isSeparator: false, currentLayoutIsRussian: false)
        }
        let effects = sm.handleManualConvert(currentLayoutIsRussian: false)
        #expect(effects == [.none])
        #expect(!effects.contains { if case .deleteCharacters = $0 { return true } else { return false } })
        #expect(sm.rawBuffer.count == 0)
    }
}
