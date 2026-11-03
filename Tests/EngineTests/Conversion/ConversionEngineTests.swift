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

    @Test func conversionModeRussianTextGoesToEnglish() {
        let e = makeEngine()
        #expect(e.conversionMode(for: "привет мир") == .toEnglish)
    }

    @Test func conversionModeEnglishTextGoesToRussian() {
        let e = makeEngine()
        #expect(e.conversionMode(for: "ghbdtn vbh") == .toRussian)
    }

    @Test func conversionModeNoLettersReturnsNil() {
        let e = makeEngine()
        #expect(e.conversionMode(for: "123 !!!") == nil)
    }

    @Test func conversionModeHalfHalfIsDeterministicToRussian() {
        let e = makeEngine()
        // Ровно 50/50 (2 кириллицы + 2 латиницы) → не «больше половины» → .toRussian
        #expect(e.conversionMode(for: "абcd") == .toRussian)
    }

    @Test func conversionModeLatinMajorityWithYoGoesToRussian() {
        let e = makeEngine()
        // ё — кириллица, но латиницы больше → .toRussian
        #expect(e.conversionMode(for: "ёghbdtn") == .toRussian)
    }

    // Реальные ANSI-позиции: «ghbdtn»↔«привет» (0x05/0x04/0x0B/0x02/0x10/0x2D),
    // «vbh»↔«мир» (0x09/0x0B/0x04), пунктуация: 0x2B ',', 0x2F '.', 0x2C '/' (EN) / '.' (RU).
    let enTable: [UInt16: Character] = [
        0x05: "g", 0x04: "h", 0x0B: "b", 0x02: "d", 0x10: "t", 0x2D: "n",
        0x09: "v", 0x2B: ",", 0x2F: ".", 0x2C: "/", 0x31: " ",
    ]
    let ruTable: [UInt16: Character] = [
        0x05: "п", 0x04: "р", 0x0B: "и", 0x02: "в", 0x10: "е", 0x2D: "т",
        0x09: "м", 0x2B: "б", 0x2F: "ю", 0x2C: ".", 0x31: " ",
    ]

    func makeRealPairsEngine() -> ConversionEngine {
        ConversionEngine(
            russianToEnglish: CharacterPairMap(pairs: ConversionEngine.buildPairs(from: ruTable, to: enTable)),
            englishToRussian: CharacterPairMap(pairs: ConversionEngine.buildPairs(from: enTable, to: ruTable)),
            keycodeToCharRU: ruTable,
            keycodeToCharEN: enTable
        )
    }

    @Test func punctuationIdentityBeatsKeycodePair() {
        // Пара по позиции 0x2B дала б бы ','→'б'; оверлей требует ','→','.
        // Обратное направление — буквенная пара: 'б'→',' (как в Punto).
        let e = makeRealPairsEngine()
        #expect(e.convert(",", mode: .toRussian) == ",")
        #expect(e.convert("б", mode: .toEnglish) == ",")
        #expect(e.convert(".", mode: .toRussian) == ".")
        #expect(e.convert("ю", mode: .toEnglish) == ".")
    }

    @Test func convertsEnglishWordWithTrailingPunctuation() {
        let e = makeRealPairsEngine()
        // Буфер «ghbdtn.»: буквы по парам, '.' — тождественно.
        #expect(e.convert("ghbdtn.", mode: .toRussian) == "привет.")
        #expect(e.convert("ghbdtn, vbh!", mode: .toRussian) == "привет, мир!")
    }

    @Test func convertsRussianTextWithPunctuationAndSpaces() {
        let e = makeRealPairsEngine()
        // Пробел и знаки конвертируются тождественно — явная identity для пробела
        // обязательна: иначе пара по позиции 0x31 (' '↔' ') внешне ок, но менее надёжна.
        #expect(e.convert("привет, мир!", mode: .toEnglish) == "ghbdtn, vbh!")
    }

    @Test func convertPreservingCaseRoundTripsRegister() {
        let e = makeRealPairsEngine()
        // D8: регистр переносится посимвольно, в обе стороны
        #expect(e.convertPreservingCase("GhbdtN", mode: .toRussian) == "ПривеТ")
        #expect(e.convertPreservingCase("ПривеТ", mode: .toEnglish) == "GhbdtN")
        // строчные — регрессия прежнего поведения
        #expect(e.convertPreservingCase("ghbdtn", mode: .toRussian) == "привет")
    }

    @Test func convertPreservingCaseLeavesCaselessCharacters() {
        let e = makeRealPairsEngine()
        // символы без регистра (цифры, пунктуация, пробел) не меняются (I6)
        #expect(e.convertPreservingCase("1., !", mode: .toRussian) == "1., !")
        #expect(e.convertPreservingCase("ghbdtn. 1", mode: .toRussian) == "привет. 1")
    }

    @Test func punctuationIdentitySetContents() {
        #expect(ConversionEngine.punctuationIdentity.contains("."))
        #expect(ConversionEngine.punctuationIdentity.contains(","))
        #expect(ConversionEngine.punctuationIdentity.contains(" "))
        #expect(ConversionEngine.punctuationIdentity.contains("«"))
        #expect(ConversionEngine.punctuationIdentity.contains("—"))
        #expect(!ConversionEngine.punctuationIdentity.contains("б"))
        #expect(!ConversionEngine.punctuationIdentity.contains("a"))
    }
}
