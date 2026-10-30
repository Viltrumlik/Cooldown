import CooldownCore
import Foundation

/// Remembers which targets the user ticked.
struct Preferences {
    private let defaults: UserDefaults
    private let key = "enabledTargets"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func isEnabled(_ info: TargetInfo) -> Bool {
        stored[info.id] ?? info.enabledByDefault
    }

    func setEnabled(_ enabled: Bool, for id: String) {
        var values = stored
        values[id] = enabled
        defaults.set(values, forKey: key)
    }

    private var stored: [String: Bool] {
        defaults.dictionary(forKey: key) as? [String: Bool] ?? [:]
    }
}
