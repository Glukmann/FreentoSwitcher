import Testing
@testable import Engine

// .serialized: the tests share and mutate the static SettingsStore.defaults,
// so they must not run concurrently. The runner on this toolchain ignores
// the test-level .serialized trait, but honors it at suite level.
@Suite(.serialized)
final class AppSettingsTests {
    init() { useIsolatedSettingsSuite() }
    deinit { restoreStandardSettingsSuite() }

    @Test func defaultsMatchSpec() {
        let d = AppSettings.default
        #expect(d.russianLayoutID == "com.apple.keylayout.RussianWin" || !d.russianLayoutID.isEmpty)
        #expect(d.englishLayoutID == "com.apple.keylayout.ABC" || !d.englishLayoutID.isEmpty)
        #expect(d.isAutocorrectionActive == true)
        #expect(d.isSoundOn == true)
        #expect(d.sounds.contains(.autoConvert))
        #expect(d.hotkeySwitchLayout == Hotkey(keycode: 50, modifiers: 0x100000)) // Cmd+`
        #expect(d.debugLogging == false)
    }

    @Test func legacyJSONWithoutDebugLoggingDecodesWithDefaultOff() {
        #expect(debugLoggingDecodedFromLegacyJSON() == false)
    }

    @Test func saveLoadRoundtrip() {
        var s = AppSettings.default
        s.excludedApps = ["com.apple.Safari"]
        s.userRules = [UserRule(pattern: "^https?://", isRegex: true, shouldSwitch: false, isActive: true)]
        s.sounds = [.switchToRussian, .undo]
        SettingsStore.save(s)
        let loaded = SettingsStore.load()
        #expect(loaded == s)
    }

    @Test func loadReturnsDefaultsWhenNothingSaved() {
        clearIsolatedSettingsSuite()
        #expect(SettingsStore.load() == .default)
    }
}
