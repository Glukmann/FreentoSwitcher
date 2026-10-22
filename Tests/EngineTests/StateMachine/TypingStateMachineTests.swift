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
        let e = sm.handleKeyDown(KeyStroke(keycode: 0x0C, modifiers: 0), isSeparator: false)
        #expect(e == [.none])
        #expect(sm.rawBuffer.count == 1)
    }

    @Test func separatorAfterTriggerWordConverts() {
        var sm = makeSM()
        // набираем "вборд" (keycode'ы условные, stringValue="вборд")
        for k: UInt16 in [0x0C, 0x2B, 0x2F, 0x1E, 0x27] {
            _ = sm.handleKeyDown(KeyStroke(keycode: k, modifiers: 0), isSeparator: false)
        }
        let effects = sm.handleKeyDown(KeyStroke(keycode: 0x31, modifiers: 0), isSeparator: true)
        #expect(effects.contains(.switchLayout))
        #expect(effects.contains(.deleteCharacters(count: 5)))
        #expect(effects.contains(.replayBuffer))
        #expect(effects.contains(.playSound(.autoConvert)))
        #expect(sm.rawBuffer.count == 0)
    }

    @Test func separatorAfterUnknownWordJustResets() {
        var sm = makeSM(triggers: ["zzzzz"])
        _ = sm.handleKeyDown(KeyStroke(keycode: 0x0C, modifiers: 0), isSeparator: false)
        let effects = sm.handleKeyDown(KeyStroke(keycode: 0x31, modifiers: 0), isSeparator: true)
        #expect(effects == [.resetBuffers])
        #expect(sm.rawBuffer.count == 0)
    }

    @Test func escapeResetsBuffers() {
        var sm = makeSM()
        _ = sm.handleKeyDown(KeyStroke(keycode: 0x0C, modifiers: 0), isSeparator: false)
        let e = sm.handleKeyDown(KeyStroke(keycode: 0x35, modifiers: 0), isSeparator: false)
        #expect(e == [.resetBuffers])
        #expect(sm.rawBuffer.count == 0)
    }

    @Test func backspaceRemovesLastStroke() {
        var sm = makeSM()
        _ = sm.handleKeyDown(KeyStroke(keycode: 0x0C, modifiers: 0), isSeparator: false)
        _ = sm.handleKeyDown(KeyStroke(keycode: 0x33, modifiers: 0), isSeparator: false)
        #expect(sm.rawBuffer.count == 0)
    }

    @Test func autocorrectionOffOnlyResets() {
        var sm = makeSM(autocorrection: false)
        _ = sm.handleKeyDown(KeyStroke(keycode: 0x0C, modifiers: 0), isSeparator: false)
        #expect(sm.rawBuffer.count == 0)
    }

    @Test func manualSwitchSetsCancelFlag() {
        var sm = makeSM(cancelAfterManualSwitch: true)
        _ = sm.handleManualLayoutSwitch()
        // после ручного переключения следующее слово не конвертируется
        for k: UInt16 in [0x0C, 0x2B, 0x2F, 0x1E, 0x27] {
            _ = sm.handleKeyDown(KeyStroke(keycode: k, modifiers: 0), isSeparator: false)
        }
        let effects = sm.handleKeyDown(KeyStroke(keycode: 0x31, modifiers: 0), isSeparator: true)
        #expect(!effects.contains(.switchLayout))
    }

    @Test func undoHotkeyReplaysUndoBuffer() {
        var sm = makeSM()
        for k: UInt16 in [0x0C, 0x2B, 0x2F, 0x1E, 0x27] {
            _ = sm.handleKeyDown(KeyStroke(keycode: k, modifiers: 0), isSeparator: false)
        }
        _ = sm.handleKeyDown(KeyStroke(keycode: 0x31, modifiers: 0), isSeparator: true) // конвертация
        let e = sm.handleUndoHotkey()
        #expect(e.contains(.switchLayout))
        #expect(e.contains(.replayBuffer))
        #expect(e.contains(.playSound(.undo)))
    }
}
