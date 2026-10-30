import Foundation

/// Something Cooldown can measure and clean: a cache folder, a set of
/// background processes, a pile of stale simulators.
///
/// Implementations must be safe to call from any thread. `scan()` must never
/// modify anything; `clean()` must only touch what `scan()` reported.
public protocol CleanTarget: Sendable {
    var info: TargetInfo { get }

    /// Measures what would be cleaned. Read-only.
    func scan() async -> ScanResult

    /// Performs the cleanup.
    func clean() async -> CleanOutcome
}

public extension CleanTarget {
    var id: String { info.id }
}

/// Static description of a target, used by the UI.
public struct TargetInfo: Sendable, Hashable, Identifiable {
    public let id: String
    public let title: String
    /// One line: what it is and what happens after cleaning.
    public let detail: String
    public let group: TargetGroup
    public let risk: Risk
    public let enabledByDefault: Bool

    public init(
        id: String,
        title: String,
        detail: String,
        group: TargetGroup,
        risk: Risk,
        enabledByDefault: Bool
    ) {
        self.id = id
        self.title = title
        self.detail = detail
        self.group = group
        self.risk = risk
        self.enabledByDefault = enabledByDefault
    }
}

public enum TargetGroup: String, Sendable, CaseIterable {
    case processes = "Background processes"
    case xcode = "Xcode & Simulators"
    case android = "Android & Gradle"
    case javascript = "JavaScript"
    case flutter = "Flutter & Dart"
    case python = "Python"
    case packageManagers = "Package managers"
    case editors = "Code editors"
    case system = "System"
}

public enum Risk: Int, Sendable, Comparable {
    /// Regenerated automatically and cheaply. Safe to clean any time.
    case safe
    /// Safe, but costs something afterwards: a re-download, a slow first
    /// build, or data that cannot be recovered (Trash).
    case caution

    public static func < (lhs: Risk, rhs: Risk) -> Bool { lhs.rawValue < rhs.rawValue }
}
