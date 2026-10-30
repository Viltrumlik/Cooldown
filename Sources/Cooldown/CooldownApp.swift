import AppKit
import SwiftUI

@main
struct CooldownApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            PopoverView()
                .environmentObject(model)
        } label: {
            Image(systemName: model.menuBarSymbol)
                .accessibilityLabel("Cooldown")
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu bar only, no Dock icon. Info.plist sets LSUIElement too; this
        // also covers `swift run`, which launches without the bundle.
        NSApp.setActivationPolicy(.accessory)
    }
}
