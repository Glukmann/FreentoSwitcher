import CoreServices
import Carbon // LMGetKbdType
import Engine

/// Читает и переключает системные раскладки клавиатуры через Text Input Sources.
public final class InputSourceManager: @unchecked Sendable {
    public static let shared = InputSourceManager()

    public init() {}

    public func currentLayoutID() -> String {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue()
        else { return "" }
        return property(source, kTISPropertyInputSourceID) as? String ?? ""
    }

    public func isCurrentRussian() -> Bool {
        isRussianLayoutID(currentLayoutID())
    }

    public func switchLanguage(russianLayoutID: String, englishLayoutID: String) {
        let targetID = isCurrentRussian() ? englishLayoutID : russianLayoutID
        guard let source = source(forLayoutID: targetID) else { return }
        TISSelectInputSource(source)
    }

    public func makeKeycodeMaps(russianLayoutID: String, englishLayoutID: String)
        -> (keycodeToCharRU: [UInt16: Character], keycodeToCharEN: [UInt16: Character]) {
        (keycodeToCharRU: charsForLayout(russianLayoutID),
         keycodeToCharEN: charsForLayout(englishLayoutID))
    }

    public func allLayoutIDs() -> [String] {
        let properties = [kTISPropertyInputSourceCategory: kTISCategoryKeyboardInputSource] as CFDictionary
        guard let list = TISCreateInputSourceList(properties, false)?.takeRetainedValue() as? [TISInputSource]
        else { return [] }
        return list.compactMap { property($0, kTISPropertyInputSourceID) as? String }
    }

    private func isRussianLayoutID(_ id: String) -> Bool {
        let lower = id.lowercased()
        return lower == "ru"
            || lower.localizedCaseInsensitiveContains("russian")
            || lower.localizedCaseInsensitiveContains("рус")
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

    private func charsForLayout(_ layoutID: String) -> [UInt16: Character] {
        guard let source = source(forLayoutID: layoutID),
              let data = property(source, kTISPropertyUnicodeKeyLayoutData) as? Data
        else { return [:] }
        let kbdType = UInt32(LMGetKbdType())
        return data.withUnsafeBytes { raw in
            guard let layout = raw.bindMemory(to: UCKeyboardLayout.self).baseAddress
            else { return [:] }
            var result: [UInt16: Character] = [:]
            for keycode: UInt16 in 0...127 {
                for mods: UInt32 in [0, UInt32(shiftKey >> 8)] { // base, shift
                    var deadKeyState: UInt32 = 0
                    var chars = [UniChar](repeating: 0, count: 8)
                    var length = 0
                    let status = UCKeyTranslate(layout, keycode, UInt16(kUCKeyActionDown), mods,
                                                kbdType, 0, &deadKeyState,
                                                chars.count, &length, &chars)
                    if status == noErr, length == 1, let scalar = Unicode.Scalar(chars[0]) {
                        // Base wins: shift-символы асимметричны между раскладками
                        // (EN shift+3 = "#", RU = "№"), а LayoutChecker всё равно
                        // lowercases буквы при проверке слова.
                        if result[keycode] == nil {
                            result[keycode] = Character(scalar)
                        }
                    }
                }
            }
            return result
        }
    }
}
