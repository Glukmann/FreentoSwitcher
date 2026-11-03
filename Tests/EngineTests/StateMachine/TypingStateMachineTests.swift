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

    @Test func plainTypingAccumulatesInBuffer() {
        var sm = makeSM()
        let e = sm.handleKeyDown(KeyStroke(keycode: 0x0C, modifiers: 0), isSeparator: false, currentLayoutIsRussian: false)
        #expect(e == [.none])
        #expect(sm.rawBuffer.count == 1)
    }

    @Test func separatorAfterTriggerWordConverts() {
        var sm = makeSM()
        // набираем "dbogl" (typed читается через EN-таблицу), триггер "dbogl"
        for k: UInt16 in [0x0C, 0x2B, 0x2F, 0x1E, 0x27] {
            _ = sm.handleKeyDown(KeyStroke(keycode: k, modifiers: 0), isSeparator: false, currentLayoutIsRussian: false)
        }
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
        for k: UInt16 in [0x0C, 0x2B, 0x2F, 0x1E, 0x27] {
            _ = sm.handleKeyDown(KeyStroke(keycode: k, modifiers: 0), isSeparator: false, currentLayoutIsRussian: false)
        }
        let effects = sm.handleKeyDown(KeyStroke(keycode: 0x31, modifiers: 0), isSeparator: true, currentLayoutIsRussian: false)
        #expect(!effects.contains(.switchLayout))
    }

    @Test func undoHotkeyReplaysUndoBuffer() {
        var sm = makeSM()
        for k: UInt16 in [0x0C, 0x2B, 0x2F, 0x1E, 0x27] {
            _ = sm.handleKeyDown(KeyStroke(keycode: k, modifiers: 0), isSeparator: false, currentLayoutIsRussian: false)
        }
        _ = sm.handleKeyDown(KeyStroke(keycode: 0x31, modifiers: 0), isSeparator: true, currentLayoutIsRussian: false) // конвертация
        let e = sm.handleUndoHotkey()
        #expect(e.contains(.switchLayout))
        // word = исходный набранный текст: undoBuffer читается через EN-таблицу
        #expect(e.contains { if case .replayText(let w, let l) = $0 {
            return w == "dbogl" && l == enLayoutID } else { return false } })
        #expect(e.contains(.playSound(.undo)))
    }

    @Test func russianLayoutWordIsNotConverted() {
        var sm = makeSM()
        for k: UInt16 in [0x0C, 0x2B, 0x2F, 0x1E, 0x27] {
            _ = sm.handleKeyDown(KeyStroke(keycode: k, modifiers: 0), isSeparator: false, currentLayoutIsRussian: true)
        }
        let effects = sm.handleKeyDown(KeyStroke(keycode: 0x31, modifiers: 0), isSeparator: true, currentLayoutIsRussian: true)
        #expect(effects == [.resetBuffers])
        #expect(!effects.contains(.switchLayout))
        // корректное русское слово не должно быть откатываемо
        let undo = sm.handleUndoHotkey()
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
        for k: UInt16 in [0x0C, 179, 0x2B, 0x2F, 0x1E, 0x27] {
            _ = sm.handleKeyDown(KeyStroke(keycode: k, modifiers: 0), isSeparator: false, currentLayoutIsRussian: false)
        }
        let effects = sm.handleKeyDown(KeyStroke(keycode: 0x31, modifiers: 0), isSeparator: true, currentLayoutIsRussian: false)
        #expect(effects.contains(.switchLayout))
        #expect(effects.contains(.deleteCharacters(count: 5)))
        #expect(effects.contains { if case .replayText(let w, _) = $0 {
            return w == "вборд" } else { return false } })
    }

    @Test func undoCoversOnlyLastConvertedWord() {
        var sm = makeSM()
        // слово1 "oo" — не триггер, undo после него пустой
        _ = sm.handleKeyDown(KeyStroke(keycode: 0x2F, modifiers: 0), isSeparator: false, currentLayoutIsRussian: false)
        _ = sm.handleKeyDown(KeyStroke(keycode: 0x2F, modifiers: 0), isSeparator: false, currentLayoutIsRussian: false)
        _ = sm.handleKeyDown(KeyStroke(keycode: 0x31, modifiers: 0), isSeparator: true, currentLayoutIsRussian: false)
        // слово2 "dbogl" — конвертируется
        for k: UInt16 in [0x0C, 0x2B, 0x2F, 0x1E, 0x27] {
            _ = sm.handleKeyDown(KeyStroke(keycode: k, modifiers: 0), isSeparator: false, currentLayoutIsRussian: false)
        }
        _ = sm.handleKeyDown(KeyStroke(keycode: 0x31, modifiers: 0), isSeparator: true, currentLayoutIsRussian: false)
        let e = sm.handleUndoHotkey()
        // undo стирает и реплеит только последнее сконвертированное слово (5), не слово1+слово2 (7)
        #expect(e.contains(.deleteCharacters(count: 5)))
        #expect(e.contains { if case .replayText(let w, _) = $0 {
            return w == "dbogl" } else { return false } })
    }

    @Test func autoConvertDisabledSkipsConversionButKeepsBuffering() {
        var sm = makeSM()
        sm.setAutoConvertEnabled(false)
        for k: UInt16 in [0x0C, 0x2B, 0x2F, 0x1E, 0x27] {
            _ = sm.handleKeyDown(KeyStroke(keycode: k, modifiers: 0), isSeparator: false, currentLayoutIsRussian: false)
        }
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
        for k: UInt16 in [0x0C, 0x2B, 0x2F, 0x1E, 0x27] {
            _ = sm.handleKeyDown(KeyStroke(keycode: k, modifiers: 0), isSeparator: false, currentLayoutIsRussian: false)
        }
        _ = sm.handleKeyDown(KeyStroke(keycode: 0x31, modifiers: 0), isSeparator: true, currentLayoutIsRussian: false)
        sm.setAutoConvertEnabled(true)
        for k: UInt16 in [0x0C, 0x2B, 0x2F, 0x1E, 0x27] {
            _ = sm.handleKeyDown(KeyStroke(keycode: k, modifiers: 0), isSeparator: false, currentLayoutIsRussian: false)
        }
        let effects = sm.handleKeyDown(KeyStroke(keycode: 0x31, modifiers: 0), isSeparator: true, currentLayoutIsRussian: false)
        #expect(effects.contains(.switchLayout))
        #expect(effects.contains(.deleteCharacters(count: 5)))
        #expect(effects.contains(.playSound(.autoConvert)))
    }

    @Test func manualConvertENtoRUForcesWithoutDictionary() {
        // триггеры НЕ совпадают — ручная конвертация не смотрит словарь
        var sm = makeSM(triggers: ["zzzzz"])
        for k: UInt16 in [0x0C, 0x2B, 0x2F, 0x1E, 0x27] {
            _ = sm.handleKeyDown(KeyStroke(keycode: k, modifiers: 0), isSeparator: false, currentLayoutIsRussian: false)
        }
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
        for k: UInt16 in [0x0C, 0x2B, 0x2F, 0x1E, 0x27] {
            _ = sm.handleKeyDown(KeyStroke(keycode: k, modifiers: 0), isSeparator: false, currentLayoutIsRussian: true)
        }
        let effects = sm.handleManualConvert(currentLayoutIsRussian: true)
        #expect(effects.contains(.switchLayout))
        #expect(effects.contains(.deleteCharacters(count: 5)))
        #expect(effects.contains { if case .replayText(let w, let l) = $0 {
            return w == "dbogl" && l == enLayoutID } else { return false } })
        #expect(effects.contains(.playSound(.autoConvert)))
    }

    @Test func manualConvertEmptyRawAndUndoBuffersDoesNothing() {
        var sm = makeSM()
        #expect(sm.handleManualConvert(currentLayoutIsRussian: false) == [.none])
    }

    @Test func repeatManualConvertAfterConvertTogglesBack() {
        // каноничное поведение Punto: повторное ⌥⌘P сразу после конвертации
        // откатывает её — реплеится исходное слово
        var sm = makeSM(triggers: ["zzzzz"])
        for k: UInt16 in [0x0C, 0x2B, 0x2F, 0x1E, 0x27] {
            _ = sm.handleKeyDown(KeyStroke(keycode: k, modifiers: 0), isSeparator: false, currentLayoutIsRussian: false)
        }
        _ = sm.handleManualConvert(currentLayoutIsRussian: false) // "dbogl" → "вборд"
        let toggleBack = sm.handleManualConvert(currentLayoutIsRussian: false)
        #expect(toggleBack.contains(.switchLayout))
        #expect(toggleBack.contains(.deleteCharacters(count: 5)))
        // откат возвращает исходный набранный текст (латиница)
        #expect(toggleBack.contains { if case .replayText(let w, let l) = $0 {
            return w == "dbogl" && l == enLayoutID } else { return false } })
        #expect(toggleBack.contains(.playSound(.undo)))
    }

    @Test func manualConvertWithSelectionSkipsUndo() {
        // активное выделение имеет приоритет над откатом слова (backspace по
        // выделению деструктивен) — engine возвращает [.none], App уйдёт
        // в конвертацию выделения
        var sm = makeSM(triggers: ["zzzzz"])
        for k: UInt16 in [0x0C, 0x2B, 0x2F, 0x1E, 0x27] {
            _ = sm.handleKeyDown(KeyStroke(keycode: k, modifiers: 0), isSeparator: false, currentLayoutIsRussian: false)
        }
        _ = sm.handleManualConvert(currentLayoutIsRussian: false) // "dbogl" → "вборд", undoBuffer непуст
        let effects = sm.handleManualConvert(currentLayoutIsRussian: false, selectionExists: true)
        #expect(effects == [.none])
    }

    @Test func manualConvertWithoutSelectionUndoWorks() {
        // регрессия: без выделения повторный хоткей откатывает слово как раньше
        var sm = makeSM(triggers: ["zzzzz"])
        for k: UInt16 in [0x0C, 0x2B, 0x2F, 0x1E, 0x27] {
            _ = sm.handleKeyDown(KeyStroke(keycode: k, modifiers: 0), isSeparator: false, currentLayoutIsRussian: false)
        }
        _ = sm.handleManualConvert(currentLayoutIsRussian: false) // "dbogl" → "вборд"
        let toggleBack = sm.handleManualConvert(currentLayoutIsRussian: false, selectionExists: false)
        #expect(toggleBack.contains(.switchLayout))
        #expect(toggleBack.contains(.deleteCharacters(count: 5)))
        #expect(toggleBack.contains { if case .replayText(let w, _) = $0 {
            return w == "dbogl" } else { return false } })
        #expect(toggleBack.contains(.playSound(.undo)))
    }

    @Test func thirdManualConvertAfterToggleBackDoesNothing() {
        // регрессия: undoBuffer после отката пуст — «третье нажатие» вхолостую
        var sm = makeSM(triggers: ["zzzzz"])
        for k: UInt16 in [0x0C, 0x2B, 0x2F, 0x1E, 0x27] {
            _ = sm.handleKeyDown(KeyStroke(keycode: k, modifiers: 0), isSeparator: false, currentLayoutIsRussian: false)
        }
        _ = sm.handleManualConvert(currentLayoutIsRussian: false)
        _ = sm.handleManualConvert(currentLayoutIsRussian: false) // откат
        #expect(sm.handleManualConvert(currentLayoutIsRussian: false) == [.none])
    }

    @Test func undoAfterManualConvertENtoRURestoresLatin() {
        var sm = makeSM()
        for k: UInt16 in [0x0C, 0x2B, 0x2F, 0x1E, 0x27] {
            _ = sm.handleKeyDown(KeyStroke(keycode: k, modifiers: 0), isSeparator: false, currentLayoutIsRussian: false)
        }
        _ = sm.handleManualConvert(currentLayoutIsRussian: false) // "dbogl" → "вборд"
        let undo = sm.handleUndoHotkey()
        #expect(undo.contains(.switchLayout))
        #expect(undo.contains(.deleteCharacters(count: 5)))
        // undo восстанавливает исходный набранный текст (латиница)
        #expect(undo.contains { if case .replayText(let w, let l) = $0 {
            return w == "dbogl" && l == enLayoutID } else { return false } })
        #expect(undo.contains(.playSound(.undo)))
    }

    @Test func undoAfterManualConvertRUtoENRestoresRussian() {
        var sm = makeSM()
        for k: UInt16 in [0x0C, 0x2B, 0x2F, 0x1E, 0x27] {
            _ = sm.handleKeyDown(KeyStroke(keycode: k, modifiers: 0), isSeparator: false, currentLayoutIsRussian: true)
        }
        _ = sm.handleManualConvert(currentLayoutIsRussian: true) // "вборд" → "dbogl"
        let undo = sm.handleUndoHotkey()
        #expect(undo.contains(.switchLayout))
        // undo восстанавливает исходный набранный текст (русское слово)
        #expect(undo.contains { if case .replayText(let w, let l) = $0 {
            return w == "вборд" && l == ruLayoutID } else { return false } })
        #expect(undo.contains(.playSound(.undo)))
    }

    @Test func undoAfterManualConvertDoesNotPoisonUndoBufferLayout() {
        var sm = makeSM()
        // RU→EN ручная конвертация: undoBuffer.layoutID = russian
        for k: UInt16 in [0x0C, 0x2B, 0x2F, 0x1E, 0x27] {
            _ = sm.handleKeyDown(KeyStroke(keycode: k, modifiers: 0), isSeparator: false, currentLayoutIsRussian: true)
        }
        _ = sm.handleManualConvert(currentLayoutIsRussian: true)
        _ = sm.handleUndoHotkey() // undo очищает undoBuffer — layoutID не должен протухать
        // печатаем новое слово в EN-раскладке и жмём undo вхолостую: штрихи должны
        // читаться через legacy-дефолт EN, а не через протухший RU layoutID
        for k: UInt16 in [0x0C, 0x2B, 0x2F] {
            _ = sm.handleKeyDown(KeyStroke(keycode: k, modifiers: 0), isSeparator: false, currentLayoutIsRussian: false)
        }
        let undo = sm.handleUndoHotkey()
        #expect(undo.contains { if case .replayText(let w, _) = $0 {
            return w == "dbo" } else { return false } }) // не "вбо"
        #expect(undo.contains(.playSound(.undo)))
    }

    @Test func manualSwitchCancelFlagDrainedWhileAutoConvertDisabled() {
        var sm = makeSM(cancelAfterManualSwitch: true)
        _ = sm.handleManualLayoutSwitch() // cancelNextWord = true
        sm.setAutoConvertEnabled(false)
        // слово, набранное пока авто-конвертация выключена
        for k: UInt16 in [0x0C, 0x2B, 0x2F, 0x1E, 0x27] {
            _ = sm.handleKeyDown(KeyStroke(keycode: k, modifiers: 0), isSeparator: false, currentLayoutIsRussian: false)
        }
        _ = sm.handleKeyDown(KeyStroke(keycode: 0x31, modifiers: 0), isSeparator: true, currentLayoutIsRussian: false)
        sm.setAutoConvertEnabled(true)
        // следующее слово конвертируется — флаг не должен пережить выключенный период
        for k: UInt16 in [0x0C, 0x2B, 0x2F, 0x1E, 0x27] {
            _ = sm.handleKeyDown(KeyStroke(keycode: k, modifiers: 0), isSeparator: false, currentLayoutIsRussian: false)
        }
        let effects = sm.handleKeyDown(KeyStroke(keycode: 0x31, modifiers: 0), isSeparator: true, currentLayoutIsRussian: false)
        #expect(effects.contains(.switchLayout))
        #expect(effects.contains(.deleteCharacters(count: 5)))
        #expect(effects.contains(.playSound(.autoConvert)))
    }

    @Test func backspaceEmptyingUndoBufferClearsStaleLayout() {
        var sm = makeSM()
        // RU→EN ручная конвертация: undoBuffer.layoutID = russian
        for k: UInt16 in [0x0C, 0x2B, 0x2F, 0x1E, 0x27] {
            _ = sm.handleKeyDown(KeyStroke(keycode: k, modifiers: 0), isSeparator: false, currentLayoutIsRussian: true)
        }
        _ = sm.handleManualConvert(currentLayoutIsRussian: true)
        // пользователь стирает слово backspace'ами — undoBuffer опустошается,
        // протухший RU layoutID не должен на нём остаться
        for _ in 0..<5 {
            _ = sm.handleKeyDown(KeyStroke(keycode: 0x33, modifiers: 0), isSeparator: false, currentLayoutIsRussian: false)
        }
        // набор нового слова в EN-раскладке и undo вхолостую: штрихи читаются
        // через legacy-дефолт EN, а не через протухший RU layoutID
        for k: UInt16 in [0x0C, 0x2B, 0x2F] {
            _ = sm.handleKeyDown(KeyStroke(keycode: k, modifiers: 0), isSeparator: false, currentLayoutIsRussian: false)
        }
        let undo = sm.handleUndoHotkey()
        #expect(undo.contains { if case .replayText(let w, _) = $0 {
            return w == "dbo" } else { return false } }) // не "вбо"
        #expect(undo.contains(.playSound(.undo)))
    }

    @Test func discardTypingBuffersPreventsPhantomDelete() {
        // selection-путь при непустом rawBuffer (набрал слово → выделил мышкой):
        // App сбрасывает буферы — иначе после сепаратора фантомный буфер
        // стёр бы чужие символы перед кареткой
        var sm = makeSM()
        for k: UInt16 in [0x0C, 0x2B, 0x2F, 0x1E, 0x27] {
            _ = sm.handleKeyDown(KeyStroke(keycode: k, modifiers: 0), isSeparator: false, currentLayoutIsRussian: false)
        }
        #expect(sm.rawBuffer.count == 5)
        sm.discardTypingBuffers()
        #expect(sm.rawBuffer.count == 0)
        let effects = sm.handleKeyDown(KeyStroke(keycode: 0x31, modifiers: 0), isSeparator: true, currentLayoutIsRussian: false)
        #expect(!effects.contains { if case .deleteCharacters = $0 { return true } else { return false } })
        #expect(effects == [.none])
    }
}
