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
        let w = word.lowercased()
        // 1. user exceptions (block conversion)
        for rule in userRules where !rule.shouldSwitch {
            if matches(rule, word: w) { return .exception }
        }
        // 2. user force-switch dictionary
        for rule in userRules where rule.shouldSwitch {
            if matches(rule, word: w) { return .incorrectLayout }
        }
        // 3. trigger words
        if triggers.contains(w) { return .incorrectLayout }
        return .unknown
    }

    private func matches(_ rule: UserRule, word: String) -> Bool {
        if rule.isRegex {
            return word.range(of: rule.pattern, options: .regularExpression) != nil
        }
        return word == rule.pattern.lowercased()
    }
}
