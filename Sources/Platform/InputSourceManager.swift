import CoreServices
import Carbon // LMGetKbdType
import Engine
import Foundation // usleep

/// Читает и переключает системные раскладки клавиатуры через Text Input Sources.
public final class InputSourceManager: @unchecked Sendable {
    public static let shared = InputSourceManager()

    public init() {}

    public func currentLayoutID() -> String {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue()
        else { return "" }
        return property(source, kTISPropertyInputSourceID) as? String ?? ""
    }

    /// Русской считаем любую раскладку, чей ID содержит "Russian"
    /// (Russian, RussianWin, ...), либо краткий ID "ru".
    public func isCurrentRussian() -> Bool {
        let id = currentLayoutID()
        return id.contains("Russian") || id == "ru"
    }

    public func switchLanguage(russianLayoutID: String, englishLayoutID: String) {
        let wantsRussian = !isCurrentRussian()
        let targetID = wantsRussian ? russianLayoutID : englishLayoutID
        // Fallback только для русской: если точный ID не найден — первый источник,
        // содержащий "Russian". Для английской точечно: не найден — лог и стоп.
        guard let source = source(forLayoutID: targetID)
            ?? (wantsRussian ? firstSource(containing: "Russian") : nil)
        else {
            DebugLogger.log("switchLanguage: layout \(targetID) not found")
            return
        }
        TISSelectInputSource(source)
    }

    /// Переключает раскладку и ждёт, пока TIS не подтвердит смену.
    /// Возвращает true, если раскладка подтверждена за timeout.
    @discardableResult
    public func switchLanguageAndWait(russianLayoutID: String, englishLayoutID: String,
                                      timeout: Duration = .milliseconds(500)) -> Bool {
        let before = currentLayoutID()
        switchLanguage(russianLayoutID: russianLayoutID, englishLayoutID: englishLayoutID)
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            let now = currentLayoutID()
            if now != before && !now.isEmpty { return true }
            usleep(5_000) // 5 мс
        }
        return false
    }

    /// Активирует КОНКРЕТНУЮ раскладку (не тоггл) — для конвертации выделения,
    /// где направление известно из текста. Fallback к firstSource("Russian") только для русской.
    public func selectLayout(russian: Bool, russianLayoutID: String, englishLayoutID: String) {
        let targetID = russian ? russianLayoutID : englishLayoutID
        guard let source = source(forLayoutID: targetID)
            ?? (russian ? firstSource(containing: "Russian") : nil) else {
            DebugLogger.log("selectLayout: \(targetID) not found")
            return
        }
        TISSelectInputSource(source)
    }

    /// Обратная таблица «символ → (keycode, нужен ли Shift)» для посимвольного
    /// keycode-реплея результата конвертации в целевой раскладке.
    public typealias CharKeyMapping = (keycode: UInt16, needsShift: Bool)

    public func makeKeycodeMaps(russianLayoutID: String, englishLayoutID: String)
        -> (keycodeToCharRU: [UInt16: Character], keycodeToCharEN: [UInt16: Character],
            charToKeyRU: [Character: CharKeyMapping], charToKeyEN: [Character: CharKeyMapping]) {
        let ru = mapsForLayout(russianLayoutID)
        let en = mapsForLayout(englishLayoutID)
        return (ru.forward, en.forward, ru.reverse, en.reverse)
    }

    /// Русской считаем любую раскладку, чей ID содержит "Russian"/"рус" либо "ru".
    /// Дублирует логику Engine (там она private) — нужна App для выбора обратной
    /// таблицы под layoutID эффекта .replayText.
    public static func isRussianLayoutID(_ id: String) -> Bool {
        let lower = id.lowercased()
        return lower == "ru"
            || lower.localizedCaseInsensitiveContains("russian")
            || lower.localizedCaseInsensitiveContains("рус")
    }

    public func allLayoutIDs() -> [String] {
        let properties = [kTISPropertyInputSourceCategory: kTISCategoryKeyboardInputSource] as CFDictionary
        guard let list = TISCreateInputSourceList(properties, false)?.takeRetainedValue() as? [TISInputSource]
        else { return [] }
        return list.compactMap { property($0, kTISPropertyInputSourceID) as? String }
    }

    /// Определяет включённые русскую и английскую раскладки.
    /// Возвращает nil для стороны, которую не удалось найти.
    public func detectLayoutIDs() -> (russian: String?, english: String?) {
        let ids = allLayoutIDs()
        let russian = ids.first {
            $0.range(of: "Russian", options: .caseInsensitive) != nil
        }
        // Порядок предпочтения: ABC → US → British/English.
        // "US" матчим case-SENSITIVE: case-insensitive "us" матчится в
        // "RUSsian"/"AUStrian" и английская сторона получила бы русскую раскладку.
        let english = ids.first {
            $0.range(of: "ABC", options: .caseInsensitive) != nil
        } ?? ids.first {
            $0.range(of: "US") != nil
        } ?? ids.first {
            $0.range(of: "British", options: .caseInsensitive) != nil
                || $0.range(of: "English", options: .caseInsensitive) != nil
        }
        return (russian, english)
    }

    private func property(_ source: TISInputSource, _ key: CFString) -> CFTypeRef? {
        guard let raw = TISGetInputSourceProperty(source, key) else { return nil }
        return Unmanaged<CFTypeRef>.fromOpaque(raw).takeUnretainedValue()
    }

    private func source(forLayoutID id: String) -> TISInputSource? {
        let properties = [kTISPropertyInputSourceID: id] as CFDictionary
        let list = TISCreateInputSourceList(properties, false)?.takeRetainedValue() as? [TISInputSource]
        return list?.first
    }

    private func firstSource(containing substring: String) -> TISInputSource? {
        let properties = [kTISPropertyInputSourceCategory: kTISCategoryKeyboardInputSource] as CFDictionary
        guard let list = TISCreateInputSourceList(properties, false)?.takeRetainedValue() as? [TISInputSource]
        else { return nil }
        return list.first {
            (property($0, kTISPropertyInputSourceID) as? String)?.contains(substring) == true
        }
    }

    /// Один проход UCKeyTranslate по keycode'ам 0...127 и слоям base/shift:
    /// собирает прямую таблицу (keycode → символ; base побеждает shift) и
    /// обратную (символ → (keycode, needsShift); для той же буквы base тоже
    /// побеждает — он обрабатывается первым).
    private func mapsForLayout(_ layoutID: String)
        -> (forward: [UInt16: Character], reverse: [Character: CharKeyMapping]) {
        guard let source = source(forLayoutID: layoutID),
              let data = property(source, kTISPropertyUnicodeKeyLayoutData) as? Data
        else { return ([:], [:]) }
        let kbdType = UInt32(LMGetKbdType())
        return data.withUnsafeBytes { raw in
            guard let layout = raw.bindMemory(to: UCKeyboardLayout.self).baseAddress
            else { return ([:], [:]) }
            var forward: [UInt16: Character] = [:]
            var reverse: [Character: CharKeyMapping] = [:]
            for keycode: UInt16 in 0...127 {
                for (mods, needsShift) in [(UInt32(0), false), (UInt32(shiftKey >> 8), true)] {
                    var deadKeyState: UInt32 = 0
                    var chars = [UniChar](repeating: 0, count: 8)
                    var length = 0
                    let status = UCKeyTranslate(layout, keycode, UInt16(kUCKeyActionDown), mods,
                                                kbdType, 0, &deadKeyState,
                                                chars.count, &length, &chars)
                    guard status == noErr, length == 1, let scalar = Unicode.Scalar(chars[0]) else {
                        continue
                    }
                    let c = Character(scalar)
                    // Base wins: shift-символы асимметричны между раскладками
                    // (EN shift+3 = "#", RU = "№"), а LayoutChecker всё равно
                    // lowercases буквы при проверке слова.
                    if forward[keycode] == nil {
                        forward[keycode] = c
                    }
                    if reverse[c] == nil {
                        reverse[c] = (keycode: keycode, needsShift: needsShift)
                    }
                }
            }
            return (forward, reverse)
        }
    }
}
