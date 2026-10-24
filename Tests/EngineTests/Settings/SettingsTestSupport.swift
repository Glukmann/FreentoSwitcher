import Foundation
import Engine

// Kept in a separate file without `import Testing`: this toolchain's build
// system loses the TestingMacros plugin path when a file imports both
// Testing and Foundation (cross-import overlay), so test suites annotated
// with @Suite fail to compile there.
func removePersistentSettingsDomain() {
    UserDefaults(suiteName: SettingsStore.defaultsSuiteName)?
        .removePersistentDomain(forName: SettingsStore.defaultsSuiteName)
}

// Декодирует JSON в формате, сохранённом до появления ключа debugLogging
// (все остальные ключи на месте). Отдельно от файла с @Test: тот не может
// импортировать Foundation вместе с Testing на этом тулчейне.
func debugLoggingDecodedFromLegacyJSON() -> Bool? {
    let legacyJSON = """
    {
        "russianLayoutID": "com.apple.keylayout.Russian",
        "englishLayoutID": "com.apple.keylayout.ABC",
        "hotkeySwitchLayout": {"keycode": 50, "modifiers": 1048576},
        "hotkeyUndo": {"keycode": 50, "modifiers": 524288},
        "hotkeyToggleAutocorrection": {"keycode": 65535, "modifiers": 0},
        "sounds": 15,
        "isSoundOn": true,
        "isAutocorrectionActive": true,
        "cancelNextWordAfterManualSwitch": false,
        "noAutoconvertAfterTabOrEnter": false,
        "excludedApps": ["com.apple.Safari"],
        "userRules": [],
        "launchesOnStartup": true
    }
    """
    guard let data = legacyJSON.data(using: .utf8),
          let s = try? JSONDecoder().decode(AppSettings.self, from: data) else { return nil }
    return s.debugLogging
}
