import Testing
@testable import Engine

struct TypingStateMachineTests {
    func makeSM(triggers: [String] = ["вборд"], autocorrection: Bool = true,
                cancelAfterManualSwitch: Bool = false) -> TypingStateMachine {
        var s = AppSettings.default
        s.isAutocorrectionActive = autocorrection
        s.cancelNextWordAfterManualSwitch = cancelAfterManualSwitch
        let engine = ConversionEngine(
            russianToEnglish: CharacterPairMap(pairs: ["в":"d","б":"j","о":"j","р":"h","д":"l"]),
            englishToRussian: CharacterPairMap(pairs: ["d":"в","j":"о"]),
            keycodeToCharRU: [0x0C:"в", 0x2F:"о", 0x2B:"б", 0x1E:"р", 0x27:"д"],
            keycodeToCharEN: [0x0C:"d", 0x2F:"o", 0x2B:"b", 0x1E:"g", 0x27:"l"])
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
        // набираем "вборд" (keycode'ы условные, stringValue="вборд")
        for k: UInt16 in [0x0C, 0x2B, 0x2F, 0x1E, 0x27] {
            _ = sm.handleKeyDown(KeyStroke(keycode: k, modifiers: 0), isSeparator: false, currentLayoutIsRussian: false)
        }
        let effects = sm.handleKeyDown(KeyStroke(keycode: 0x31, modifiers: 0), isSeparator: true, currentLayoutIsRussian: false)
        #expect(effects.contains(.switchLayout))
        #expect(effects.contains(.deleteCharacters(count: 5)))
        #expect(effects.contains { if case .replayBuffer(let s) = $0 { return s.count == 5 } else { return false } })
        #expect(effects.contains(.playSound(.autoConvert)))
        #expect(sm.rawBuffer.count == 0)
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
        #expect(e.contains { if case .replayBuffer(let s) = $0 { return s.count == 5 } else { return false } })
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

    @Test func undoCoversOnlyLastConvertedWord() {
        var sm = makeSM()
        // слово1 "оо" — не триггер, undo после него пустой
        _ = sm.handleKeyDown(KeyStroke(keycode: 0x2F, modifiers: 0), isSeparator: false, currentLayoutIsRussian: false)
        _ = sm.handleKeyDown(KeyStroke(keycode: 0x2F, modifiers: 0), isSeparator: false, currentLayoutIsRussian: false)
        _ = sm.handleKeyDown(KeyStroke(keycode: 0x31, modifiers: 0), isSeparator: true, currentLayoutIsRussian: false)
        // слово2 "вборд" — конвертируется
        for k: UInt16 in [0x0C, 0x2B, 0x2F, 0x1E, 0x27] {
            _ = sm.handleKeyDown(KeyStroke(keycode: k, modifiers: 0), isSeparator: false, currentLayoutIsRussian: false)
        }
        _ = sm.handleKeyDown(KeyStroke(keycode: 0x31, modifiers: 0), isSeparator: true, currentLayoutIsRussian: false)
        let e = sm.handleUndoHotkey()
        // undo стирает и реплеит только последнее сконвертированное слово (5), не слово1+слово2 (7)
        #expect(e.contains(.deleteCharacters(count: 5)))
        #expect(e.contains { if case .replayBuffer(let s) = $0 { return s.count == 5 } else { return false } })
    }
}
