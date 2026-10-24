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
    public var debugLogging: Bool

    public init(russianLayoutID: String, englishLayoutID: String, hotkeySwitchLayout: Hotkey, hotkeyUndo: Hotkey, hotkeyToggleAutocorrection: Hotkey, sounds: SoundMask, isSoundOn: Bool, isAutocorrectionActive: Bool, cancelNextWordAfterManualSwitch: Bool, noAutoconvertAfterTabOrEnter: Bool, excludedApps: [String], userRules: [UserRule], launchesOnStartup: Bool, debugLogging: Bool = false) {
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
        self.debugLogging = debugLogging
    }

    // Синтезированный decode ломался бы на JSON, сохранённом до появления
    // debugLogging (keyNotFound → load() молча сбрасывал бы все настройки
    // на .default), поэтому decode ручной: новый ключ читается с дефолтом.
    private enum CodingKeys: String, CodingKey {
        case russianLayoutID, englishLayoutID, hotkeySwitchLayout, hotkeyUndo
        case hotkeyToggleAutocorrection, sounds, isSoundOn, isAutocorrectionActive
        case cancelNextWordAfterManualSwitch, noAutoconvertAfterTabOrEnter
        case excludedApps, userRules, launchesOnStartup, debugLogging
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        russianLayoutID = try c.decode(String.self, forKey: .russianLayoutID)
        englishLayoutID = try c.decode(String.self, forKey: .englishLayoutID)
        hotkeySwitchLayout = try c.decode(Hotkey.self, forKey: .hotkeySwitchLayout)
        hotkeyUndo = try c.decode(Hotkey.self, forKey: .hotkeyUndo)
        hotkeyToggleAutocorrection = try c.decode(Hotkey.self, forKey: .hotkeyToggleAutocorrection)
        sounds = try c.decode(SoundMask.self, forKey: .sounds)
        isSoundOn = try c.decode(Bool.self, forKey: .isSoundOn)
        isAutocorrectionActive = try c.decode(Bool.self, forKey: .isAutocorrectionActive)
        cancelNextWordAfterManualSwitch = try c.decode(Bool.self, forKey: .cancelNextWordAfterManualSwitch)
        noAutoconvertAfterTabOrEnter = try c.decode(Bool.self, forKey: .noAutoconvertAfterTabOrEnter)
        excludedApps = try c.decode([String].self, forKey: .excludedApps)
        userRules = try c.decode([UserRule].self, forKey: .userRules)
        launchesOnStartup = try c.decode(Bool.self, forKey: .launchesOnStartup)
        debugLogging = try c.decodeIfPresent(Bool.self, forKey: .debugLogging) ?? false
    }

    public static let `default` = AppSettings(
        russianLayoutID: "com.apple.keylayout.Russian",
        englishLayoutID: "com.apple.keylayout.ABC",
        hotkeySwitchLayout: Hotkey(keycode: 50, modifiers: 0x100000), // Cmd+`
        hotkeyUndo: Hotkey(keycode: 50, modifiers: 0x80000),          // Option+`
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
