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
