import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// Stops background processes that keep eating RAM and CPU after you are
/// done with them, such as Gradle and Kotlin daemons.
///
/// Only processes owned by the current user are touched, and they get a
/// polite SIGTERM so they can shut down cleanly.
public struct ProcessTarget: CleanTarget {
    public let info: TargetInfo
    /// Substrings matched against the full command line (`pgrep -f`).
    public let patterns: [String]
    /// Hide the row when this path (relative to home) does not exist, so
    /// people who never used the tool don't see it.
    public let requiredRelativePath: String?
    private let home: URL

    public init(
        info: TargetInfo,
        patterns: [String],
        requiredRelativePath: String? = nil,
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) {
        self.info = info
        self.patterns = patterns
        self.requiredRelativePath = requiredRelativePath
        self.home = home
    }

    public func scan() async -> ScanResult {
        if let requiredRelativePath,
           !FileManager.default.fileExists(atPath: home.appendingPathComponent(requiredRelativePath).path) {
            return .notApplicable
        }
        let pids = await matchingPIDs()
        return pids.isEmpty ? .empty : .processes(count: pids.count)
    }

    public func clean() async -> CleanOutcome {
        let pids = await matchingPIDs()
        guard !pids.isEmpty else { return CleanOutcome(targetID: info.id) }

        for pid in pids {
            kill(pid, SIGTERM)
        }
        // Give them a moment to exit gracefully.
        try? await Task.sleep(nanoseconds: 2_000_000_000)

        let stillRunning = Set(await matchingPIDs()).intersection(pids)
        let stopped = pids.count - stillRunning.count
        let errors = stillRunning.isEmpty
            ? []
            : ["\(info.title): \(stillRunning.count) process(es) did not stop"]
        return CleanOutcome(targetID: info.id, stoppedProcesses: stopped, errors: errors)
    }

    private func matchingPIDs() async -> [Int32] {
        let uid = String(getuid())
        var pids = Set<Int32>()
        for pattern in patterns {
            let result = await Shell.run("/usr/bin/pgrep", ["-u", uid, "-f", pattern], timeout: 10)
            pids.formUnion(ProcessListParser.pids(from: result.stdout))
        }
        pids.remove(getpid())
        return pids.sorted()
    }
}
