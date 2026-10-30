import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// Access to `xcrun simctl`, guarded so it never pops up the
/// "install developer tools" dialog on Macs without Xcode.
enum Simctl {
    static func isInstalled(home: URL) async -> Bool {
        let devices = home.appendingPathComponent("Library/Developer/CoreSimulator/Devices")
        guard FileManager.default.fileExists(atPath: devices.path) else { return false }
        // `xcrun` triggers an install prompt when tools are missing;
        // `xcode-select -p` only prints an error. Command Line Tools alone
        // have no simctl, so treat that like "not installed" too.
        let result = await Shell.run("/usr/bin/xcode-select", ["-p"], timeout: 5)
        return result.succeeded && !result.stdout.contains("CommandLineTools")
    }

    static func run(_ arguments: [String], timeout: TimeInterval = 60) async -> Shell.Result {
        await Shell.run("/usr/bin/xcrun", ["simctl"] + arguments, timeout: timeout)
    }

    static func devices(_ filter: [String] = []) async -> [SimulatorDevice]? {
        let result = await run(["list", "devices"] + filter + ["-j"], timeout: 30)
        guard result.succeeded else { return nil }
        return try? SimctlParser.devices(from: Data(result.stdout.utf8))
    }
}

/// Shuts down booted iOS/watchOS/tvOS simulators.
///
/// A booted simulator keeps burning CPU (`SimMetalHost`, `backboardd`...)
/// even after its window is closed. On Intel MacBooks that heat alone can
/// throttle the CPU to half speed.
public struct BootedSimulatorsTarget: CleanTarget {
    public let info: TargetInfo
    private let home: URL

    public init(info: TargetInfo, home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.info = info
        self.home = home
    }

    public func scan() async -> ScanResult {
        guard await Simctl.isInstalled(home: home) else { return .notApplicable }
        guard let devices = await Simctl.devices(["booted"]) else {
            return .unavailable(reason: "Could not ask Xcode for simulators (xcrun simctl failed).")
        }
        let booted = devices.filter { $0.state == "Booted" }.count
        return booted == 0 ? .empty : .processes(count: booted)
    }

    public func clean() async -> CleanOutcome {
        guard await Simctl.isInstalled(home: home),
              let devices = await Simctl.devices(["booted"]) else {
            return CleanOutcome(targetID: info.id)
        }
        let booted = devices.filter { $0.state == "Booted" }.count
        guard booted > 0 else { return CleanOutcome(targetID: info.id) }

        let result = await Simctl.run(["shutdown", "all"], timeout: 90)
        await quitSimulatorApp()

        guard result.succeeded else {
            return CleanOutcome(targetID: info.id, errors: ["\(info.title): \(result.stderr.trimmed)"])
        }
        return CleanOutcome(targetID: info.id, stoppedProcesses: booted)
    }

    /// Closes the now-empty Simulator window.
    private func quitSimulatorApp() async {
        let result = await Shell.run("/usr/bin/pgrep", ["-u", String(getuid()), "-x", "Simulator"], timeout: 5)
        for pid in ProcessListParser.pids(from: result.stdout) {
            kill(pid, SIGTERM)
        }
    }
}

/// Deletes simulators whose runtime is no longer installed. They can never
/// boot again but keep their disk images around.
public struct UnavailableSimulatorsTarget: CleanTarget {
    public let info: TargetInfo
    private let home: URL

    public init(info: TargetInfo, home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.info = info
        self.home = home
    }

    public func scan() async -> ScanResult {
        guard await Simctl.isInstalled(home: home) else { return .notApplicable }
        guard let devices = await Simctl.devices() else {
            return .unavailable(reason: "Could not ask Xcode for simulators (xcrun simctl failed).")
        }
        let unavailable = devices.filter { $0.isAvailable == false }
        guard !unavailable.isEmpty else { return .empty }

        let devicesFolder = home.appendingPathComponent("Library/Developer/CoreSimulator/Devices")
        let bytes = unavailable.reduce(Int64(0)) { total, device in
            total + DiskUsage.size(of: devicesFolder.appendingPathComponent(device.udid))
        }
        return .files(bytes: bytes, items: unavailable.count)
    }

    public func clean() async -> CleanOutcome {
        let before = await scan()
        guard before.hasWork else { return CleanOutcome(targetID: info.id) }

        let result = await Simctl.run(["delete", "unavailable"], timeout: 120)
        guard result.succeeded else {
            return CleanOutcome(targetID: info.id, errors: ["\(info.title): \(result.stderr.trimmed)"])
        }
        return CleanOutcome(targetID: info.id, freedBytes: before.bytes)
    }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
