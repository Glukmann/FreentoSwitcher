import Foundation

/// Детальный runtime-лог для диагностики (клавиши, хоткеи, эффекты, тап).
///
/// Глобально включается через `isEnabled` (в приложении — переключателем
/// Debug Logging в меню иконки, персистентным через AppSettings). В выключенном
/// состоянии `log` не вычисляет аргумент (autoclosure) и не трогает диск —
/// накладные расходы нулевые. Запись сериализована serial-очередью; при размере
/// файла больше 1 МБ файл перезаписывается свежей строкой.
public enum DebugLogger {
    private static let queue = DispatchQueue(label: "com.freento.debuglogger")
    // Все чтения/записи — только через queue.sync (см. isEnabled/log), гонок нет.
    nonisolated(unsafe) private static var enabled = false

    private static let maxFileSize = 1_048_576 // 1 МБ

    private static func makeFormatter() -> ISO8601DateFormatter {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }

    public static var isEnabled: Bool {
        get { queue.sync { enabled } }
        set { queue.sync { enabled = newValue } }
    }

    public static var logFileURL: URL {
        URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("freento-debug.log")
    }

    /// Ленивый лог: при isEnabled == false message() не вызывается вообще.
    public static func log(_ message: @autoclosure () -> String) {
        guard isEnabled else { return }
        let text = message()
        queue.sync {
            append("\(makeFormatter().string(from: Date())) \(text)\n")
        }
    }

    private static func append(_ line: String) {
        let url = logFileURL
        if let size = try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? UInt64,
           size > maxFileSize {
            try? FileManager.default.removeItem(at: url)
        }
        let data = Data(line.utf8)
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        } else {
            try? data.write(to: url)
        }
    }
}
