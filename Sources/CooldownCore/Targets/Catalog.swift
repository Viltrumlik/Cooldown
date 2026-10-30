import Foundation

/// Everything Cooldown knows how to clean.
///
/// Rules for adding an entry (see CONTRIBUTING.md):
/// - `detail` must say what happens *after* cleaning.
/// - Anything that costs a re-download, a slow rebuild or cannot be undone
///   is `.caution` and off by default.
/// - Keep ids stable: they are the keys for the user's saved choices.
public enum Catalog {
    public static func defaultTargets(
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> [any CleanTarget] {
        [
            // MARK: Background processes

            BootedSimulatorsTarget(
                info: TargetInfo(
                    id: "simulators.booted",
                    title: "Running simulators",
                    detail: "Shuts down booted simulators. They keep using CPU even with the window closed.",
                    group: .processes, risk: .safe, enabledByDefault: true
                ),
                home: home
            ),
            ProcessTarget(
                info: TargetInfo(
                    id: "gradle.daemons",
                    title: "Gradle & Kotlin daemons",
                    detail: "Stops idle build daemons (often 1–2 GB of RAM each). Interrupts a build that is running right now.",
                    group: .processes, risk: .safe, enabledByDefault: true
                ),
                patterns: ["GradleDaemon", "KotlinCompileDaemon"],
                requiredRelativePath: ".gradle",
                home: home
            ),

            // MARK: Xcode & Simulators

            DirectoryTarget(
                info: TargetInfo(
                    id: "xcode.derivedData",
                    title: "Xcode DerivedData",
                    detail: "Build products and indexes. Xcode recreates them; the next build is slower.",
                    group: .xcode, risk: .safe, enabledByDefault: true
                ),
                roots: ["Library/Developer/Xcode/DerivedData"],
                home: home
            ),
            DirectoryTarget(
                info: TargetInfo(
                    id: "xcode.caches",
                    title: "Xcode caches",
                    detail: "Xcode's own cache folder. Rebuilt automatically.",
                    group: .xcode, risk: .safe, enabledByDefault: true
                ),
                roots: ["Library/Caches/com.apple.dt.Xcode"],
                home: home
            ),
            UnavailableSimulatorsTarget(
                info: TargetInfo(
                    id: "simulators.unavailable",
                    title: "Unavailable simulators",
                    detail: "Simulators for OS versions that are no longer installed. They can never boot again.",
                    group: .xcode, risk: .safe, enabledByDefault: true
                ),
                home: home
            ),
            DirectoryTarget(
                info: TargetInfo(
                    id: "simulators.caches",
                    title: "Simulator caches",
                    detail: "Runtime caches. Rebuilt the next time a simulator boots.",
                    group: .xcode, risk: .safe, enabledByDefault: true
                ),
                roots: ["Library/Developer/CoreSimulator/Caches"],
                home: home
            ),
            DirectoryTarget(
                info: TargetInfo(
                    id: "xcode.deviceSupport",
                    title: "Device support files",
                    detail: "Symbols copied from devices you plugged in. Copied again (slowly) when you reconnect a device.",
                    group: .xcode, risk: .caution, enabledByDefault: false
                ),
                roots: [
                    "Library/Developer/Xcode/iOS DeviceSupport",
                    "Library/Developer/Xcode/watchOS DeviceSupport",
                    "Library/Developer/Xcode/tvOS DeviceSupport",
                    "Library/Developer/Xcode/visionOS DeviceSupport"
                ],
                home: home
            ),
            DirectoryTarget(
                info: TargetInfo(
                    id: "xcode.archives",
                    title: "Xcode archives",
                    detail: "Old release builds and their dSYMs. You need dSYMs to read crash reports of shipped versions.",
                    group: .xcode, risk: .caution, enabledByDefault: false
                ),
                roots: ["Library/Developer/Xcode/Archives"],
                home: home
            ),

            // MARK: Android & Gradle

            DirectoryTarget(
                info: TargetInfo(
                    id: "gradle.caches",
                    title: "Gradle caches",
                    detail: "Downloaded dependencies and build cache. Downloaded again on the next build.",
                    group: .android, risk: .caution, enabledByDefault: false
                ),
                roots: [".gradle/caches"],
                home: home
            ),

            // MARK: JavaScript

            DirectoryTarget(
                info: TargetInfo(
                    id: "npm.cache",
                    title: "npm cache",
                    detail: "Downloaded packages. npm fetches them again when needed.",
                    group: .javascript, risk: .safe, enabledByDefault: true
                ),
                roots: [".npm/_cacache"],
                home: home
            ),
            DirectoryTarget(
                info: TargetInfo(
                    id: "yarn.cache",
                    title: "Yarn cache",
                    detail: "Downloaded packages. Yarn fetches them again when needed.",
                    group: .javascript, risk: .safe, enabledByDefault: true
                ),
                roots: ["Library/Caches/Yarn"],
                home: home
            ),
            DirectoryTarget(
                info: TargetInfo(
                    id: "bun.cache",
                    title: "Bun cache",
                    detail: "Downloaded packages. Bun fetches them again when needed.",
                    group: .javascript, risk: .safe, enabledByDefault: true
                ),
                roots: [".bun/install/cache"],
                home: home
            ),

            // MARK: Flutter & Dart

            DirectoryTarget(
                info: TargetInfo(
                    id: "pub.cache",
                    title: "Dart pub cache",
                    detail: "Downloaded packages. Run `flutter pub get` in your projects afterwards.",
                    group: .flutter, risk: .caution, enabledByDefault: false
                ),
                roots: [".pub-cache/hosted", ".pub-cache/git"],
                home: home
            ),

            // MARK: Python

            DirectoryTarget(
                info: TargetInfo(
                    id: "pip.cache",
                    title: "pip cache",
                    detail: "Downloaded wheels. pip fetches them again when needed.",
                    group: .python, risk: .safe, enabledByDefault: true
                ),
                roots: ["Library/Caches/pip"],
                home: home
            ),

            // MARK: Package managers

            DirectoryTarget(
                info: TargetInfo(
                    id: "homebrew.cache",
                    title: "Homebrew downloads",
                    detail: "Installer files kept after `brew install`. Not needed once installed.",
                    group: .packageManagers, risk: .safe, enabledByDefault: true
                ),
                roots: ["Library/Caches/Homebrew"],
                home: home
            ),
            DirectoryTarget(
                info: TargetInfo(
                    id: "cocoapods.cache",
                    title: "CocoaPods cache",
                    detail: "Downloaded pods. Fetched again on the next `pod install`.",
                    group: .packageManagers, risk: .safe, enabledByDefault: true
                ),
                roots: ["Library/Caches/CocoaPods"],
                home: home
            ),

            // MARK: Code editors

            DirectoryTarget(
                info: TargetInfo(
                    id: "editors.caches",
                    title: "Editor caches",
                    detail: "Electron caches of VS Code, Cursor, Windsurf and VSCodium. Quit the editors first.",
                    group: .editors, risk: .caution, enabledByDefault: false
                ),
                roots: editorCacheRoots,
                home: home
            ),

            // MARK: System

            DirectoryTarget(
                info: TargetInfo(
                    id: "system.appCaches",
                    title: "Other app caches",
                    detail: "Caches of your other apps (Apple's are left alone). Apps rebuild them and may feel slower once.",
                    group: .system, risk: .caution, enabledByDefault: false
                ),
                roots: ["Library/Caches"],
                // Owned by the targets above, or by macOS itself.
                excludingNames: ["com.apple.dt.Xcode", "Yarn", "pip", "Homebrew", "CocoaPods"],
                excludingPrefixes: ["com.apple."],
                home: home
            ),
            DirectoryTarget(
                info: TargetInfo(
                    id: "system.trash",
                    title: "Trash",
                    detail: "Empties the Trash. This cannot be undone.",
                    group: .system, risk: .caution, enabledByDefault: false
                ),
                roots: [".Trash"],
                home: home
            )
        ]
    }

    static let editorCacheRoots: [String] = {
        let editors = ["Code", "Code - Insiders", "Cursor", "Windsurf", "VSCodium"]
        let caches = ["Cache", "CachedData", "Code Cache", "GPUCache", "CachedExtensionVSIXs"]
        return editors.flatMap { editor in
            caches.map { "Library/Application Support/\(editor)/\($0)" }
        }
    }()
}
