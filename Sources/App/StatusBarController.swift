import AppKit

@MainActor
final class StatusBarController: NSObject {
    private let item: NSStatusItem
    var onSwitchLayout: (() -> Void)?
    var onToggleAutocorrection: (() -> Void)?
    var onQuit: (() -> Void)?

    override init() {
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        item.button?.title = "⇄"
        buildMenu()
    }

    private func buildMenu() {
        let menu = NSMenu()
        let switchItem = NSMenuItem(title: "Switch Layout", action: #selector(switchLayout), keyEquivalent: "")
        let toggleItem = NSMenuItem(title: "Toggle Autocorrection", action: #selector(toggleAutocorrection), keyEquivalent: "")
        let quitItem = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
        for i in [switchItem, toggleItem, NSMenuItem.separator(), quitItem] { menu.addItem(i) }
        menu.items.forEach { $0.target = self }
        item.menu = menu
    }

    @objc private func switchLayout() { onSwitchLayout?() }
    @objc private func toggleAutocorrection() { onToggleAutocorrection?() }
    @objc private func quit() { onQuit?() }
}
