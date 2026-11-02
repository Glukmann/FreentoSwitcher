import AppKit

@MainActor
final class StatusBarController: NSObject {
    private let item: NSStatusItem
    private let debugLoggingItem: NSMenuItem
    private let autoConversionItem: NSMenuItem
    var onSwitchLayout: (() -> Void)?
    var onToggleAutocorrection: (() -> Void)?
    var onToggleDebugLogging: (() -> Void)?
    var onConvertLastWord: (() -> Void)?
    var onToggleAutoConversion: (() -> Void)?
    var onQuit: (() -> Void)?

    override init() {
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        debugLoggingItem = NSMenuItem(title: "Debug Logging", action: #selector(toggleDebugLogging), keyEquivalent: "")
        autoConversionItem = NSMenuItem(title: "Auto Conversion", action: #selector(toggleAutoConversion), keyEquivalent: "")
        super.init()
        item.button?.title = "⇄"
        buildMenu()
    }

    private func buildMenu() {
        let menu = NSMenu()
        let convertItem = NSMenuItem(title: "Convert Last Word", action: #selector(convertLastWord), keyEquivalent: "")
        let switchItem = NSMenuItem(title: "Switch Layout", action: #selector(switchLayout), keyEquivalent: "")
        let toggleItem = NSMenuItem(title: "Toggle Autocorrection", action: #selector(toggleAutocorrection), keyEquivalent: "")
        let quitItem = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
        for i in [convertItem, switchItem, NSMenuItem.separator(),
                  autoConversionItem, toggleItem, debugLoggingItem,
                  NSMenuItem.separator(), quitItem] { menu.addItem(i) }
        menu.items.forEach { $0.target = self }
        item.menu = menu
    }

    /// Галочка Debug Logging — вызывается после загрузки настроек и после переключения.
    func setDebugLoggingOn(_ on: Bool) {
        debugLoggingItem.state = on ? .on : .off
    }

    /// Галочка Auto Conversion — вызывается после загрузки настроек и после переключения.
    func setAutoConversionOn(_ on: Bool) {
        autoConversionItem.state = on ? .on : .off
    }

    @objc private func convertLastWord() { onConvertLastWord?() }
    @objc private func switchLayout() { onSwitchLayout?() }
    @objc private func toggleAutocorrection() { onToggleAutocorrection?() }
    @objc private func toggleDebugLogging() { onToggleDebugLogging?() }
    @objc private func toggleAutoConversion() { onToggleAutoConversion?() }
    @objc private func quit() { onQuit?() }
}
