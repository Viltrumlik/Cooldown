import Foundation

/// The last line of defence before anything is deleted.
///
/// Every file target declares a root folder (for example
/// `~/Library/Developer/Xcode/DerivedData`) and Cooldown only ever deletes the
/// *children* of that root. `PathGuard` makes sure that:
///
/// - the root really lives inside the user's home folder, even after
///   resolving symlinks (a symlinked `~/.npm -> /` is refused);
/// - the root is not the home folder itself or one of the folders that hold
///   user data (`~/Documents`, `~/Library`, ...);
/// - every child about to be deleted is a direct child of that root.
public struct PathGuard: Sendable {
    public let home: URL

    /// Folders that must never be used as a root, relative to home.
    public static let protectedRelativePaths: [String] = [
        "",
        "Library",
        "Library/Application Support",
        "Library/Containers",
        "Library/Group Containers",
        "Library/Mobile Documents",
        "Library/Mail",
        "Library/Messages",
        "Library/Keychains",
        "Library/Preferences",
        "Library/Developer",
        "Library/Developer/Xcode",
        "Library/Developer/CoreSimulator",
        "Documents",
        "Desktop",
        "Downloads",
        "Pictures",
        "Movies",
        "Music",
        "Public",
        ".ssh",
        ".gnupg"
    ]

    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.home = home.standardizedFileURL.resolvingSymlinksInPath()
    }

    public enum Violation: Error, Equatable, CustomStringConvertible {
        case outsideHome(String)
        case protectedFolder(String)
        case notADirectChild(child: String, root: String)

        public var description: String {
            switch self {
            case let .outsideHome(path): return "Refused: \(path) is outside your home folder"
            case let .protectedFolder(path): return "Refused: \(path) is a protected folder"
            case let .notADirectChild(child, root): return "Refused: \(child) is not inside \(root)"
            }
        }
    }

    /// Validates a cleanup root. Returns the resolved URL that should be used.
    public func validateRoot(_ root: URL) throws -> URL {
        let resolved = root.standardizedFileURL.resolvingSymlinksInPath()
        let homeComponents = home.pathComponents
        let rootComponents = resolved.pathComponents

        guard rootComponents.count > homeComponents.count,
              Array(rootComponents.prefix(homeComponents.count)) == homeComponents else {
            throw Violation.outsideHome(resolved.path)
        }

        let relative = rootComponents.dropFirst(homeComponents.count).joined(separator: "/")
        let isProtected = Self.protectedRelativePaths.contains {
            $0.caseInsensitiveCompare(relative) == .orderedSame
        }
        if isProtected {
            throw Violation.protectedFolder(resolved.path)
        }
        return resolved
    }

    /// Validates that `child` is a direct child of an already validated root.
    /// The child itself is not resolved: if it is a symlink, the link is what
    /// gets removed, never the thing it points to.
    public func validateChild(_ child: URL, ofValidatedRoot root: URL) throws {
        let parent = child.standardizedFileURL.deletingLastPathComponent().resolvingSymlinksInPath()
        let name = child.lastPathComponent
        guard parent.pathComponents == root.pathComponents,
              !name.isEmpty, name != ".", name != ".." else {
            throw Violation.notADirectChild(child: child.path, root: root.path)
        }
    }
}
