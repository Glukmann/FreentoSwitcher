import ServiceManagement

@MainActor
enum LaunchAtLogin {
    static func setEnabled(_ enabled: Bool) {
        try? SMAppService.mainApp.unregister()
        if enabled { try? SMAppService.mainApp.register() }
    }

    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }
}
