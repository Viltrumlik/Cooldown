import Foundation

/// Empties one or more folders (cache folders, build folders) while keeping
/// the folders themselves.
///
/// Every deletion is checked by `PathGuard`: roots must live inside the home
/// folder and only their direct children are removed.
public struct DirectoryTarget: CleanTarget {
    public let info: TargetInfo
    /// Folders to empty, relative to the home folder.
    public let relativeRoots: [String]
    /// Child names to keep (for example, folders owned by another target).
    public let excludedNames: Set<String>
    /// Child name prefixes to keep (for example, `com.apple.`).
    public let excludedPrefixes: [String]
    private let pathGuard: PathGuard

    public init(
        info: TargetInfo,
        roots relativeRoots: [String],
        excludingNames excludedNames: Set<String> = [],
        excludingPrefixes excludedPrefixes: [String] = [],
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) {
        self.info = info
        self.relativeRoots = relativeRoots
        self.excludedNames = excludedNames
        self.excludedPrefixes = excludedPrefixes
        self.pathGuard = PathGuard(home: home)
    }

    // Walking big folders is blocking I/O. Run it on GCD so it never starves
    // Swift's small cooperative thread pool (status updates, timers...).
    public func scan() async -> ScanResult {
        await offloaded { self.scanBlocking() }
    }

    public func clean() async -> CleanOutcome {
        await offloaded { self.cleanBlocking() }
    }

    private func offloaded<T>(_ work: @escaping @Sendable () -> T) async -> T {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                continuation.resume(returning: work())
            }
        }
    }

    private func scanBlocking() -> ScanResult {
        let roots = existingRoots()
        guard !roots.isEmpty else { return .notApplicable }

        var bytes: Int64 = 0
        var items = 0
        var permissionDenied = false

        for root in roots {
            do {
                let validated = try pathGuard.validateRoot(root)
                let children = try removableChildren(of: validated)
                items += children.count
                for child in children {
                    bytes += DiskUsage.size(of: child)
                }
            } catch let violation as PathGuard.Violation {
                return .unavailable(reason: violation.description)
            } catch {
                permissionDenied = true
            }
        }

        if items == 0 {
            return permissionDenied
                ? .unavailable(reason: "macOS blocked access. Give Cooldown Full Disk Access in System Settings → Privacy & Security.")
                : .empty
        }
        return .files(bytes: bytes, items: items)
    }

    private func cleanBlocking() -> CleanOutcome {
        var freed: Int64 = 0
        var failures = 0
        var firstError: String?

        for root in existingRoots() {
            let validated: URL
            let children: [URL]
            do {
                validated = try pathGuard.validateRoot(root)
                children = try removableChildren(of: validated)
            } catch {
                failures += 1
                firstError = firstError ?? "\(error)"
                continue
            }

            for child in children {
                do {
                    try pathGuard.validateChild(child, ofValidatedRoot: validated)
                    let size = DiskUsage.size(of: child)
                    try FileManager.default.removeItem(at: child)
                    freed += size
                } catch {
                    // Typical cause: a file owned by the system or in use.
                    failures += 1
                    firstError = firstError ?? "\(child.lastPathComponent): \(error.localizedDescription)"
                }
            }
        }

        var errors: [String] = []
        if let firstError {
            errors.append(failures == 1
                ? "\(info.title): \(firstError)"
                : "\(info.title): \(failures) items skipped (first: \(firstError))")
        }
        return CleanOutcome(targetID: info.id, freedBytes: freed, errors: errors)
    }

    // MARK: - Helpers

    private func existingRoots() -> [URL] {
        relativeRoots.compactMap { relative in
            let url = pathGuard.home.appendingPathComponent(relative, isDirectory: true)
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
                  isDirectory.boolValue else { return nil }
            return url
        }
    }

    private func removableChildren(of root: URL) throws -> [URL] {
        try FileManager.default
            .contentsOfDirectory(at: root, includingPropertiesForKeys: nil, options: [])
            .filter { child in
                let name = child.lastPathComponent
                return !excludedNames.contains(name)
                    && !excludedPrefixes.contains(where: { name.hasPrefix($0) })
            }
    }
}
