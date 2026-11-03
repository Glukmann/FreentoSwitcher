import Testing
@testable import Engine

struct KeyStrokeBufferTests {
    @Test func appendsAndCounts() {
        var b = KeyStrokeBuffer()
        b.append(KeyStroke(keycode: 0x0C, modifiers: 0))
        b.append(KeyStroke(keycode: 0x0D, modifiers: 0))
        #expect(b.count == 2)
    }

    @Test func capsAtMaxLength() {
        var b = KeyStrokeBuffer()
        for i in 0..<40 { b.append(KeyStroke(keycode: UInt16(i % 50), modifiers: 0)) }
        #expect(b.count == 32)
    }

    @Test func overflowFlagSetOnTrimAndClearedOnReset() {
        var b = KeyStrokeBuffer()
        for i in 0..<32 { b.append(KeyStroke(keycode: UInt16(i), modifiers: 0)) }
        #expect(!b.overflowed) // ровно maxLength — ещё не переполнение
        b.append(KeyStroke(keycode: 200, modifiers: 0)) // 33-й штрих → обрезка
        #expect(b.count == 32)
        #expect(b.overflowed)
        b.removeAll()
        #expect(!b.overflowed)
        // то же при стирании до пустого removeLast
        for i in 0..<33 { b.append(KeyStroke(keycode: UInt16(i % 50), modifiers: 0)) }
        #expect(b.overflowed)
        for _ in 0..<32 { b.removeLast() }
        #expect(!b.overflowed)
    }

    @Test func removeLastAndRemoveAll() {
        var b = KeyStrokeBuffer()
        b.append(KeyStroke(keycode: 1, modifiers: 0))
        b.removeLast()
        #expect(b.count == 0)
        b.append(KeyStroke(keycode: 2, modifiers: 0))
        b.removeAll()
        #expect(b.count == 0)
    }

    @Test func punctuationCounters() {
        var b = KeyStrokeBuffer()
        b.append(KeyStroke(keycode: 0x2F, modifiers: 0)) // "." period key
        b.append(KeyStroke(keycode: 0x0C, modifiers: 0))
        b.append(KeyStroke(keycode: 0x2C, modifiers: 0)) // "/" slash key
        #expect(b.punctuationMarksCount == 2)
        #expect(b.beginsWithPunctuation)
        var b2 = KeyStrokeBuffer()
        b2.append(KeyStroke(keycode: 0x0C, modifiers: 0))
        #expect(!b2.beginsWithPunctuation)
    }

    @Test func stringValueReadsShiftLayerByModifierFlag() {
        let engine = ConversionEngine(
            russianToEnglish: CharacterPairMap(pairs: [:]),
            englishToRussian: CharacterPairMap(pairs: [:]),
            keycodeToCharRU: [0x0C: "в"],
            keycodeToCharEN: [0x0C: "d"],
            keycodeToCharShiftRU: [0x0C: "В"],
            keycodeToCharShiftEN: [0x0C: "D"])
        var b = KeyStrokeBuffer()
        b.layoutID = "com.apple.keylayout.ABC"
        b.append(KeyStroke(keycode: 0x0C, modifiers: 0))
        b.append(KeyStroke(keycode: 0x0C, modifiers: 0x20000)) // Shift-флаг
        #expect(b.stringValue(convertingWith: engine) == "dD")
        // Shift-флаг без shift-символа в таблице → fallback на base
        let engineNoShift = ConversionEngine(
            russianToEnglish: CharacterPairMap(pairs: [:]),
            englishToRussian: CharacterPairMap(pairs: [:]),
            keycodeToCharRU: [0x0C: "в"],
            keycodeToCharEN: [0x0C: "d"])
        var b2 = KeyStrokeBuffer()
        b2.layoutID = "com.apple.keylayout.ABC"
        b2.append(KeyStroke(keycode: 0x0C, modifiers: 0x20000))
        #expect(b2.stringValue(convertingWith: engineNoShift) == "d")
    }
}
