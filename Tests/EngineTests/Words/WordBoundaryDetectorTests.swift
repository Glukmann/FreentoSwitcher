import Testing
@testable import Engine

struct WordBoundaryDetectorTests {
    @Test func spaceTabEnterAreSeparatorsInEnglishLayout() {
        let d = WordBoundaryDetector(noAutoconvertAfterTabOrEnter: false)
        #expect(d.isWordSeparator(0x31, englishLayout: true)) // space
        #expect(d.isWordSeparator(0x24, englishLayout: true)) // enter
        #expect(d.isWordSeparator(0x30, englishLayout: true)) // tab
    }

    @Test func backspaceAndEscapeAreNotSeparatorsInEnglishLayout() {
        let d = WordBoundaryDetector(noAutoconvertAfterTabOrEnter: false)
        #expect(!d.isWordSeparator(0x33, englishLayout: true)) // backspace
        #expect(!d.isWordSeparator(0x35, englishLayout: true)) // escape
        #expect(!d.isWordSeparator(0x0C, englishLayout: true)) // letter
    }

    @Test func tabEnterExcludedWhenNoAutoconvertFlag() {
        let d = WordBoundaryDetector(noAutoconvertAfterTabOrEnter: true)
        #expect(!d.isWordSeparator(0x30, englishLayout: true))
        #expect(!d.isWordSeparator(0x24, englishLayout: true))
        #expect(d.isWordSeparator(0x31, englishLayout: true))
    }

    @Test func spaceTabEnterAreSeparatorsInRussianLayout() {
        let d = WordBoundaryDetector(noAutoconvertAfterTabOrEnter: false)
        #expect(d.isWordSeparator(0x31, englishLayout: false)) // space
        #expect(d.isWordSeparator(0x24, englishLayout: false)) // enter
        #expect(d.isWordSeparator(0x30, englishLayout: false)) // tab
    }

    @Test func letterKeysAreNotSeparatorsInRussianLayout() {
        // В RU-раскладке эти клавиши печатают буквы и не должны разрывать слова:
        // 0x27 э, 0x2B б, 0x2F ю, 0x2C ., 0x29 ж, 0x1B ё-ряд
        let d = WordBoundaryDetector(noAutoconvertAfterTabOrEnter: false)
        #expect(!d.isWordSeparator(0x27, englishLayout: false))
        #expect(!d.isWordSeparator(0x2B, englishLayout: false))
        #expect(!d.isWordSeparator(0x2F, englishLayout: false))
        #expect(!d.isWordSeparator(0x2C, englishLayout: false))
        #expect(!d.isWordSeparator(0x29, englishLayout: false))
        #expect(!d.isWordSeparator(0x1B, englishLayout: false))
        #expect(!d.isWordSeparator(0x33, englishLayout: false)) // backspace
        #expect(!d.isWordSeparator(0x35, englishLayout: false)) // escape
        #expect(!d.isWordSeparator(0x0C, englishLayout: false)) // letter
    }
}
