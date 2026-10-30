import ServiceManagement

/// Thin wrapper over SMAppService (macOS 13+). Works when running from the
/// built Cooldown.app bundle, not from `swift run`.
enum LaunchAtLogin {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func set(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}
