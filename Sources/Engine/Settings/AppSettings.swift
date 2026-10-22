import Foundation

public struct UserRule: Codable, Equatable, Sendable {
    public var pattern: String
    public var isRegex: Bool
    public var shouldSwitch: Bool
    public var isActive: Bool

    public init(pattern: String, isRegex: Bool, shouldSwitch: Bool, isActive: Bool) {
        self.pattern = pattern
        self.isRegex = isRegex
        self.shouldSwitch = shouldSwitch
        self.isActive = isActive
    }
}

public struct AppSettings: Codable, Equatable, Sendable {
    public var russianLayoutID: String
    public var englishLayoutID: String
    public var hotkeySwitchLayout: Hotkey
    public var hotkeyUndo: Hotkey
    public var hotkeyToggleAutocorrection: Hotkey
    public var sounds: SoundMask
    public var isSoundOn: Bool
    public var isAutocorrectionActive: Bool
    public var cancelNextWordAfterManualSwitch: Bool
    public var noAutoconvertAfterTabOrEnter: Bool
    public var excludedApps: [String]
    public var userRules: [UserRule]
    public var launchesOnStartup: Bool

    public init(russianLayoutID: String, englishLayoutID: String, hotkeySwitchLayout: Hotkey, hotkeyUndo: Hotkey, hotkeyToggleAutocorrection: Hotkey, sounds: SoundMask, isSoundOn: Bool, isAutocorrectionActive: Bool, cancelNextWordAfterManualSwitch: Bool, noAutoconvertAfterTabOrEnter: Bool, excludedApps: [String], userRules: [UserRule], launchesOnStartup: Bool) {
        self.russianLayoutID = russianLayoutID
        self.englishLayoutID = englishLayoutID
        self.hotkeySwitchLayout = hotkeySwitchLayout
        self.hotkeyUndo = hotkeyUndo
        self.hotkeyToggleAutocorrection = hotkeyToggleAutocorrection
        self.sounds = sounds
        self.isSoundOn = isSoundOn
        self.isAutocorrectionActive = isAutocorrectionActive
        self.cancelNextWordAfterManualSwitch = cancelNextWordAfterManualSwitch
        self.noAutoconvertAfterTabOrEnter = noAutoconvertAfterTabOrEnter
        self.excludedApps = excludedApps
        self.userRules = userRules
        self.launchesOnStartup = launchesOnStartup
    }

    public static let `default` = AppSettings(
        russianLayoutID: "com.apple.keylayout.Russian",
        englishLayoutID: "com.apple.keylayout.ABC",
        hotkeySwitchLayout: Hotkey(keycode: 49, modifiers: 0x100000), // Cmd+`
        hotkeyUndo: Hotkey(keycode: 49, modifiers: 0x80000),          // Option+`
        hotkeyToggleAutocorrection: Hotkey.none,
        sounds: [.switchToRussian, .switchToEnglish, .autoConvert, .undo],
        isSoundOn: true,
        isAutocorrectionActive: true,
        cancelNextWordAfterManualSwitch: false,
        noAutoconvertAfterTabOrEnter: false,
        excludedApps: [],
        userRules: [],
        launchesOnStartup: true
    )
}

public enum SettingsStore {
    public static let defaultsSuiteName = "com.freento.FreentoSwitcher"
    private static let key = "settings.v1"

    public static func load() -> AppSettings {
        guard let data = UserDefaults(suiteName: defaultsSuiteName)?.data(forKey: key),
              let s = try? JSONDecoder().decode(AppSettings.self, from: data) else {
            return .default
        }
        return s
    }

    public static func save(_ settings: AppSettings) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        let d = UserDefaults(suiteName: defaultsSuiteName)!
        d.set(data, forKey: key)
    }
}
