public enum ConversionMode: Equatable, Sendable {
    case toRussian
    case toEnglish
}

public struct CharacterPairMap: Equatable, Sendable {
    private let pairs: [Character: Character]

    public init(pairs: [Character: Character]) {
        self.pairs = pairs
    }

    public func convert(_ c: Character) -> Character {
        pairs[c] ?? c
    }
}

public struct ConversionEngine: Sendable {
    /// Знаки пунктуации конвертируются ТОЖДЕСТВЕННО: '.' → '.', ',' → ',' и т.д.
    /// Меняются только БУКВЫ (по клавиатурным парам). Без этого оверлея пары
    /// «по позиции клавиши» ломали бы знаки: 0x2B EN=',' ↔ RU='б' — это буква,
    /// не пара. Пробел включён явно: пара по позиции 0x31 дала бы ' '↔' ' и так,
    /// но явная identity надёжнее. Буквы (в т.ч. кириллица) в набор НЕ входят —
    /// их пары строятся только по keycode-таблицам.
    public static let punctuationIdentity: Set<Character> = [
        ".", ",", ";", ":", "!", "?", "'", "\"", "(", ")",
        "-", "–", "—", "_", "/", "\\", "@", "#", "$", "%",
        "^", "&", "*", "+", "=", "<", ">", "`", "~", "[",
        "]", "{", "}", "|", "«", "»", "„", "“", "”", " ",
    ]

    private let russianToEnglish: CharacterPairMap
    private let englishToRussian: CharacterPairMap
    private let keycodeToCharRU: [UInt16: Character]
    private let keycodeToCharEN: [UInt16: Character]

    public init(russianToEnglish: CharacterPairMap,
                englishToRussian: CharacterPairMap,
                keycodeToCharRU: [UInt16: Character],
                keycodeToCharEN: [UInt16: Character]) {
        self.russianToEnglish = russianToEnglish
        self.englishToRussian = englishToRussian
        self.keycodeToCharRU = keycodeToCharRU
        self.keycodeToCharEN = keycodeToCharEN
    }

    public func convert(_ string: String, mode: ConversionMode) -> String {
        let map = mode == .toEnglish ? russianToEnglish : englishToRussian
        return String(string.map { map.convert($0) })
    }

    /// Пары «источник → приёмник» по позициям клавиш (один keycode в двух
    /// раскладках), плюс тождественные пары для пунктуации: оверлей накладывается
    /// ПОСЛЕ keycode-пар и побеждает их (0x2B: ','→'б' затирается в ','→',').
    /// Живёт в Engine (а не в App), чтобы тестировать оверлей без App-таргета.
    public static func buildPairs(from: [UInt16: Character], to: [UInt16: Character])
        -> [Character: Character] {
        var pairs: [Character: Character] = [:]
        for (kc, dst) in to {
            if let src = from[kc], src != dst { pairs[src] = dst }
        }
        for p in punctuationIdentity { pairs[p] = p }
        return pairs
    }

    /// Направление конвертации для готового ТЕКСТА (выделения): по преобладающему
    /// алфавиту. Буквы смотрим только латиницу/кириллицу; если букв нет — nil.
    public func conversionMode(for text: String) -> ConversionMode? {
        let letters = text.filter { $0.isLetter }
        guard !letters.isEmpty else { return nil }
        let cyrillic = letters.filter { Self.isCyrillic($0) }.count
        return cyrillic * 2 > letters.count ? .toEnglish : .toRussian
    }

    static func isCyrillic(_ c: Character) -> Bool {
        guard let s = c.unicodeScalars.first, c.unicodeScalars.count == 1 else { return false }
        return (0x0400...0x04FF).contains(s.value) || s.value == 0x0451 // ё
    }

    public func isCharacterKey(_ keycode: UInt16) -> Bool {
        keycodeToCharRU[keycode] != nil || keycodeToCharEN[keycode] != nil
    }

    public func string(for strokes: [KeyStroke], layoutID: String) -> String {
        let table = isRussianLayoutID(layoutID) ? keycodeToCharRU : keycodeToCharEN
        return String(strokes.compactMap { table[$0.keycode] })
    }

    private func isRussianLayoutID(_ id: String) -> Bool {
        let lower = id.lowercased()
        return lower == "ru"
            || lower.localizedCaseInsensitiveContains("russian")
            || lower.localizedCaseInsensitiveContains("рус")
    }
}
