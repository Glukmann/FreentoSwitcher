import Testing
@testable import Engine

struct WordBoundaryDetectorTests {
    @Test func spaceTabEnterAreSeparators() {
        let d = WordBoundaryDetector(noAutoconvertAfterTabOrEnter: false)
        #expect(d.isWordSeparator(0x31)) // space
        #expect(d.isWordSeparator(0x24)) // enter
        #expect(d.isWordSeparator(0x30)) // tab
    }

    @Test func backspaceAndEscapeAreNotSeparators() {
        let d = WordBoundaryDetector(noAutoconvertAfterTabOrEnter: false)
        #expect(!d.isWordSeparator(0x33)) // backspace
        #expect(!d.isWordSeparator(0x35)) // escape
        #expect(!d.isWordSeparator(0x0C)) // letter
    }

    @Test func tabEnterExcludedWhenNoAutoconvertFlag() {
        let d = WordBoundaryDetector(noAutoconvertAfterTabOrEnter: true)
        #expect(!d.isWordSeparator(0x30))
        #expect(!d.isWordSeparator(0x24))
        #expect(d.isWordSeparator(0x31))
    }
}
