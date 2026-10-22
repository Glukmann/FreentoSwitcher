import Testing
@testable import Engine

struct ConversionEngineTests {
    let ru2en = CharacterPairMap(pairs: ["ф": "a", "ы": "s", "й": "q"])
    let en2ru = CharacterPairMap(pairs: ["a": "ф", "s": "ы", "q": "й"])

    func makeEngine() -> ConversionEngine {
        ConversionEngine(
            russianToEnglish: ru2en, englishToRussian: en2ru,
            keycodeToCharRU: [0x0C: "ф", 0x0D: "ы"],
            keycodeToCharEN: [0x0C: "a", 0x0D: "s"]
        )
    }

    @Test func convertsRussianWordToEnglish() {
        let e = makeEngine()
        #expect(e.convert("фы", mode: .toEnglish) == "as")
    }

    @Test func convertsEnglishWordToRussian() {
        let e = makeEngine()
        #expect(e.convert("as", mode: .toRussian) == "фы")
    }

    @Test func keepsUnknownCharacters() {
        let e = makeEngine()
        #expect(e.convert("a1!", mode: .toRussian) == "ф1!")
    }

    @Test func stringFromStrokesUsesLayoutMap() {
        let e = makeEngine()
        let strokes = [KeyStroke(keycode: 0x0C, modifiers: 0), KeyStroke(keycode: 0x0D, modifiers: 0)]
        #expect(e.string(for: strokes, layoutID: "ru") == "фы")
        #expect(e.string(for: strokes, layoutID: "en") == "as")
    }
}
