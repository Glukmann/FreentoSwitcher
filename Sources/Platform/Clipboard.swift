import AppKit
import CoreGraphics

/// Полный снапшот буфера обмена: элементы с raw-данными всех типов.
/// Нужен, чтобы вернуть пользователю буфер в исходном виде — там могут быть
/// файлы/картинки/RTF, которые String-представлением теряются.
public struct PasteboardSnapshot: Sendable {
    public struct Item: Sendable {
        public var types: [String]
        public var data: [String: Data]
    }
    public var items: [Item]
}

/// Доступ к общему буферу обмена для конвертации выделения.
public enum Clipboard: Sendable {
    /// Копирует выделение (Cmd+C) и ждёт смены changeCount до timeout.
    /// Возвращает скопированную строку и снапшот буфера ДО копирования
    /// (восстановить — через restore(snapshot) на всех путях, где был grabSelection).
    public static func grabSelection(timeoutMilliseconds: Int = 250)
        -> (copied: String, snapshot: PasteboardSnapshot)? {
        let pb = NSPasteboard.general
        let beforeCount = pb.changeCount
        let snapshot = takeSnapshot()
        DebugLogger.log("grab: start changeCount=\(beforeCount)")
        EventSynth.pressKeyCombination([.maskCommand], key: 0x08) // Cmd+C
        let deadline = ContinuousClock.now + .milliseconds(timeoutMilliseconds)
        while ContinuousClock.now < deadline {
            if pb.changeCount != beforeCount {
                // changeCount изменился — приложение перезаписало буфер (Cmd+C сработал).
                // Не-текст/пусто: восстанавливаем снапшот, иначе буфер пользователя потерян.
                guard let s = pb.string(forType: .string), !s.isEmpty else {
                    DebugLogger.log("grab: change but no string, restoring snapshot")
                    restore(snapshot)
                    return nil
                }
                DebugLogger.log("grab: copied count=\(s.count)")
                return (s, snapshot)
            }
            usleep(5_000)
        }
        // changeCount не изменился — буфер не трогали, восстанавливать нечего.
        DebugLogger.log("grab: timeout after \(timeoutMilliseconds)ms")
        return nil // выделения нет / приложение не отдало текст
    }

    /// Пишет строку в буфер и вставляет (Cmd+V). Вызывать ДО восстановления буфера.
    /// Остаточный риск: верифицировать, что приложение реально обработало Cmd+V,
    /// у pasteboard нет API — поэтому между paste и restore ждут фиксированные
    /// 300 мс (см. convertSelection); под нагрузкой вставка может не успеть и
    /// вставит уже восстановленное содержимое.
    public static func paste(_ string: String) {
        DebugLogger.log("paste: \(string.count) chars")
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(string, forType: .string)
        EventSynth.pressKeyCombination([.maskCommand], key: 0x09) // Cmd+V
    }

    /// Полное восстановление снапшота (все типы, все элементы, исходный порядок).
    public static func restore(_ snapshot: PasteboardSnapshot) {
        DebugLogger.log("clipboard restored")
        let pb = NSPasteboard.general
        pb.clearContents()
        let items = snapshot.items.map { saved -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for type in saved.types {
                if let d = saved.data[type] {
                    item.setData(d, forType: NSPasteboard.PasteboardType(type))
                }
            }
            return item
        }
        pb.writeObjects(items)
    }

    private static func takeSnapshot() -> PasteboardSnapshot {
        let pb = NSPasteboard.general
        var items: [PasteboardSnapshot.Item] = []
        for item in pb.pasteboardItems ?? [] {
            var data: [String: Data] = [:]
            for type in item.types {
                if let d = item.data(forType: type) { data[type.rawValue] = d }
            }
            items.append(PasteboardSnapshot.Item(types: item.types.map(\.rawValue), data: data))
        }
        return PasteboardSnapshot(items: items)
    }
}
