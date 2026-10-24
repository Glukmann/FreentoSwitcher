import Foundation
import Platform

// Kept in a separate file without `import Testing`: this toolchain's build
// system loses the TestingMacros plugin path when a file imports both
// Testing and Foundation (cross-import overlay), so test suites annotated
// with @Suite fail to compile there. Same constraint as EngineTests' support.

func removeDebugLogFile() {
    try? FileManager.default.removeItem(at: DebugLogger.logFileURL)
}

func debugLogFileExists() -> Bool {
    FileManager.default.fileExists(atPath: DebugLogger.logFileURL.path)
}

func debugLogLineCount() -> Int {
    guard let text = try? String(contentsOf: DebugLogger.logFileURL) else { return 0 }
    return text.split(separator: "\n", omittingEmptySubsequences: true).count
}

// Счётчик вычислений сообщения: ленивость log() при isEnabled == false
// проверяется через побочный эффект внутри autoclosure.
nonisolated(unsafe) var debugMessageEvaluations = 0

func logViaDisabledLoggerWithSideEffect() {
    DebugLogger.isEnabled = false
    DebugLogger.log("side effect \(incrementDebugMessageEvaluations())")
}

func incrementDebugMessageEvaluations() -> Int {
    debugMessageEvaluations += 1
    return debugMessageEvaluations
}

func resetDebugMessageEvaluations() {
    debugMessageEvaluations = 0
}
