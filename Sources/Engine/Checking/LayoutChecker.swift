import Foundation

public enum LayoutVerdict: Equatable, Sendable {
    case unknown
    case incorrectLayout
    case exception
}

public struct LayoutChecker: Sendable {
    private let triggers: Set<String>
    private let userRules: [UserRule]

    public init(triggers: [String], userRules: [UserRule]) {
        self.triggers = Set(triggers.map { $0.lowercased() })
        self.userRules = userRules.filter(\.isActive)
    }

    public func check(_ word: String, isEnglishLayout: Bool) -> LayoutVerdict {
        // Проверка идёт по ЯДРУ слова: обрезке не-букв с двух концов. В буфере
        // теперь бывает пунктуация («ghbdtn.»), и она не должна мешать поиску
        // триггера. Слово целиком (с пунктуацией) остаётся для конвертации —
        // вердикта достаточно.
        let core = Self.letterCore(of: word).lowercased()
        guard !core.isEmpty else { return .unknown }
        // 1. user exceptions (block conversion)
        for rule in userRules where !rule.shouldSwitch {
            if matches(rule, word: core) { return .exception }
        }
        // 2. user force-switch dictionary
        for rule in userRules where rule.shouldSwitch {
            if matches(rule, word: core) { return .incorrectLayout }
        }
        // 3. trigger words
        if triggers.contains(core) { return .incorrectLayout }
        return .unknown
    }

    /// Обрезает не-буквы с двух концов. trimmingCharacters не подходит:
    /// нужны именно буквы (Character.isLetter), а не CharacterSet'ы.
    static func letterCore(of word: String) -> String {
        var chars = Array(word)
        while let first = chars.first, !first.isLetter { chars.removeFirst() }
        while let last = chars.last, !last.isLetter { chars.removeLast() }
        return String(chars)
    }

    private func matches(_ rule: UserRule, word: String) -> Bool {
        if rule.isRegex {
            return word.range(of: rule.pattern, options: .regularExpression) != nil
        }
        return word == rule.pattern.lowercased()
    }
}
