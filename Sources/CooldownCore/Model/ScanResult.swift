import Foundation

/// What a scan found.
public enum ScanResult: Sendable, Equatable {
    /// The tool or folder does not exist on this Mac. The UI hides the row.
    case notApplicable
    /// Present, but there is nothing to clean right now.
    case empty
    /// Files that can be removed.
    case files(bytes: Int64, items: Int)
    /// Running processes that can be stopped.
    case processes(count: Int)
    /// Present, but could not be measured (for example, missing permission).
    case unavailable(reason: String)

    public var bytes: Int64 {
        if case let .files(bytes, _) = self { return bytes }
        return 0
    }

    public var processCount: Int {
        if case let .processes(count) = self { return count }
        return 0
    }

    /// True when cleaning would actually do something.
    public var hasWork: Bool {
        switch self {
        case let .files(bytes, items): return bytes > 0 || items > 0
        case let .processes(count): return count > 0
        case .notApplicable, .empty, .unavailable: return false
        }
    }
}

/// What a clean did.
public struct CleanOutcome: Sendable, Equatable {
    public let targetID: String
    public let freedBytes: Int64
    public let stoppedProcesses: Int
    public let errors: [String]

    public init(targetID: String, freedBytes: Int64 = 0, stoppedProcesses: Int = 0, errors: [String] = []) {
        self.targetID = targetID
        self.freedBytes = freedBytes
        self.stoppedProcesses = stoppedProcesses
        self.errors = errors
    }

    public var succeeded: Bool { errors.isEmpty }
}

/// Summary of one Clean button press.
public struct CleanReport: Sendable, Equatable {
    public let outcomes: [CleanOutcome]
    public let finishedAt: Date

    public init(outcomes: [CleanOutcome], finishedAt: Date = Date()) {
        self.outcomes = outcomes
        self.finishedAt = finishedAt
    }

    public var freedBytes: Int64 { outcomes.reduce(0) { $0 + $1.freedBytes } }
    public var stoppedProcesses: Int { outcomes.reduce(0) { $0 + $1.stoppedProcesses } }
    public var errors: [String] { outcomes.flatMap(\.errors) }
}
