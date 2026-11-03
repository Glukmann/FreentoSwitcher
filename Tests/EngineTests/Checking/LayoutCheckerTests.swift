import Testing
@testable import Engine

struct LayoutCheckerTests {
    let triggers = ["вборд", "цщкдв", "фзз", "сдуфк", "фывапролджэ"]

    @Test func triggerWordIsIncorrectLayout() {
        let c = LayoutChecker(triggers: triggers, userRules: [])
        #expect(c.check("вборд", isEnglishLayout: true) == .incorrectLayout)
    }

    @Test func nonTriggerWordIsUnknown() {
        let c = LayoutChecker(triggers: triggers, userRules: [])
        #expect(c.check("ыьфззще", isEnglishLayout: true) == .unknown)
    }

    @Test func userExceptionRuleBlocksConversion() {
        let rules = [UserRule(pattern: "^http", isRegex: true, shouldSwitch: false, isActive: true)]
        let c = LayoutChecker(triggers: triggers, userRules: rules)
        #expect(c.check("http", isEnglishLayout: true) == .exception)
    }

    @Test func inactiveRuleIsIgnored() {
        let rules = [UserRule(pattern: "вборд", isRegex: false, shouldSwitch: false, isActive: false)]
        let c = LayoutChecker(triggers: [], userRules: rules)
        #expect(c.check("вборд", isEnglishLayout: true) == .unknown)
    }

    @Test func userForceRuleTriggersConversion() {
        let rules = [UserRule(pattern: "мойдомен", isRegex: false, shouldSwitch: true, isActive: true)]
        let c = LayoutChecker(triggers: [], userRules: rules)
        #expect(c.check("мойдомен", isEnglishLayout: true) == .incorrectLayout)
    }

    @Test func triggerWithTrailingPunctuationMatchesByCore() {
        // В буфере теперь бывает пунктуация («ghbdtn.») — проверка по ядру.
        let c = LayoutChecker(triggers: ["ghbdtn"], userRules: [])
        #expect(c.check("ghbdtn.", isEnglishLayout: true) == .incorrectLayout)
    }

    @Test func triggerWrappedInPunctuationMatchesByCore() {
        let c = LayoutChecker(triggers: ["привет"], userRules: [])
        #expect(c.check(",привет,", isEnglishLayout: false) == .incorrectLayout)
    }

    @Test func triggerWrappedInHyphensMatchesByCore() {
        let c = LayoutChecker(triggers: ["проверка"], userRules: [])
        #expect(c.check("-проверка-", isEnglishLayout: false) == .incorrectLayout)
    }

    @Test func digitsOnlyWordIsUnknown() {
        let c = LayoutChecker(triggers: ["123"], userRules: [])
        #expect(c.check("123", isEnglishLayout: true) == .unknown)
        #expect(c.check("!!!", isEnglishLayout: true) == .unknown)
    }

    @Test func exceptionRuleMatchesByCore() {
        let rules = [UserRule(pattern: "^http", isRegex: true, shouldSwitch: false, isActive: true)]
        let c = LayoutChecker(triggers: [], userRules: rules)
        #expect(c.check("http://", isEnglishLayout: true) == .exception)
    }
}
