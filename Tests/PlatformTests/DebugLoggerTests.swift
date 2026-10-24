import Testing
@testable import Platform

// .serialized: тесты делят один файл лога и глобальный isEnabled,
// параллельный запуск соседних кейсов давал бы гонки.
@Suite(.serialized)
struct DebugLoggerTests {
    @Test func disabledWritesNothingAndSkipsMessageEvaluation() {
        resetDebugMessageEvaluations()
        removeDebugLogFile()
        DebugLogger.isEnabled = false
        logViaDisabledLoggerWithSideEffect()
        #expect(debugLogFileExists() == false)
        #expect(debugMessageEvaluations == 0)
    }

    @Test func enabledAppendsOneLine() {
        removeDebugLogFile()
        DebugLogger.isEnabled = true
        defer {
            DebugLogger.isEnabled = false
            removeDebugLogFile()
        }
        DebugLogger.log("hello")
        #expect(debugLogLineCount() == 1)
    }

    @Test func twoCallsAppendTwoLines() {
        removeDebugLogFile()
        DebugLogger.isEnabled = true
        defer {
            DebugLogger.isEnabled = false
            removeDebugLogFile()
        }
        DebugLogger.log("one")
        DebugLogger.log("two")
        #expect(debugLogLineCount() == 2)
    }
}
