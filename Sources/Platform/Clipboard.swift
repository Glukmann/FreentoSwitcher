import AppKit
import CoreGraphics

/// Доступ к общему буферу обмена для конвертации выделения.
public enum Clipboard: Sendable {
    /// Копирует выделение (Cmd+C) и ждёт смены changeCount до timeout.
    /// Возвращает скопированную строку и содержимое буфера ДО копирования (для восстановления).
    public static func grabSelection(timeoutMilliseconds: Int = 150)
        -> (copied: String, previous: String?)? {
        let pb = NSPasteboard.general
        let beforeCount = pb.changeCount
        let previous = pb.string(forType: .string)
        EventSynth.pressKeyCombination([.maskCommand], key: 0x08) // Cmd+C
        let deadline = ContinuousClock.now + .milliseconds(timeoutMilliseconds)
        while ContinuousClock.now < deadline {
            if pb.changeCount != beforeCount {
                guard let s = pb.string(forType: .string), !s.isEmpty else { return nil }
                return (s, previous)
            }
            usleep(5_000)
        }
        return nil // выделения нет / приложение не отдало текст
    }

    /// Пишет строку в буфер и вставляет (Cmd+V). Вызывать ДО восстановления буфера.
    public static func paste(_ string: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(string, forType: .string)
        EventSynth.pressKeyCombination([.maskCommand], key: 0x09) // Cmd+V
    }

    /// Возвращает буферу исходную строку (после того, как вставка успела сработать).
    public static func restore(_ previous: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(previous, forType: .string)
    }
}
