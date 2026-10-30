import Foundation
#if canImport(Darwin)
import Darwin
#endif

public enum ThermalLevel: Int, Sendable, Comparable {
    case nominal, fair, serious, critical

    public static func < (lhs: ThermalLevel, rhs: ThermalLevel) -> Bool { lhs.rawValue < rhs.rawValue }

    public var label: String {
        switch self {
        case .nominal: return "Normal"
        case .fair: return "Warm"
        case .serious: return "Hot"
        case .critical: return "Critical"
        }
    }
}

public enum MemoryPressure: Int32, Sendable {
    case normal = 1
    case warning = 2
    case critical = 4

    public var label: String {
        switch self {
        case .normal: return "normal"
        case .warning: return "high"
        case .critical: return "critical"
        }
    }
}

/// A point-in-time view of the things that make a Mac feel slow.
public struct SystemSnapshot: Sendable, Equatable {
    /// Intel only. 100 = full speed, lower = throttled by heat.
    public var cpuSpeedLimit: Int?
    public var thermal: ThermalLevel
    /// Same number as `memory_pressure`'s "System-wide memory free percentage".
    public var memoryFreePercent: Int?
    public var memoryPressure: MemoryPressure?
    public var physicalMemory: Int64
    public var swap: SwapUsage?
    public var diskFree: Int64?
    public var diskTotal: Int64?
    public var topProcesses: [ProcessSample]
    public var takenAt: Date

    public init(
        cpuSpeedLimit: Int? = nil,
        thermal: ThermalLevel = .nominal,
        memoryFreePercent: Int? = nil,
        memoryPressure: MemoryPressure? = nil,
        physicalMemory: Int64 = 0,
        swap: SwapUsage? = nil,
        diskFree: Int64? = nil,
        diskTotal: Int64? = nil,
        topProcesses: [ProcessSample] = [],
        takenAt: Date = Date()
    ) {
        self.cpuSpeedLimit = cpuSpeedLimit
        self.thermal = thermal
        self.memoryFreePercent = memoryFreePercent
        self.memoryPressure = memoryPressure
        self.physicalMemory = physicalMemory
        self.swap = swap
        self.diskFree = diskFree
        self.diskTotal = diskTotal
        self.topProcesses = topProcesses
        self.takenAt = takenAt
    }

    /// True when heat is slowing the Mac down.
    public var isThrottled: Bool {
        (cpuSpeedLimit ?? 100) < 90 || thermal >= .serious
    }
}

public enum SystemMonitor {
    /// Full snapshot. Takes well under a second.
    public static func snapshot(topProcessCount: Int = 5) async -> SystemSnapshot {
        async let speed = cpuSpeedLimit()
        async let swap = swapUsage()
        async let processes = topProcesses(limit: topProcessCount)
        let disk = diskSpace()

        return await SystemSnapshot(
            cpuSpeedLimit: speed,
            thermal: thermalLevel(),
            memoryFreePercent: memoryFreePercent(),
            memoryPressure: memoryPressure(),
            physicalMemory: Int64(ProcessInfo.processInfo.physicalMemory),
            swap: swap,
            diskFree: disk.free,
            diskTotal: disk.total,
            topProcesses: processes
        )
    }

    public static func cpuSpeedLimit() async -> Int? {
        let result = await Shell.run("/usr/bin/pmset", ["-g", "therm"], timeout: 5)
        return PmsetParser.cpuSpeedLimit(from: result.stdout)
    }

    public static func thermalLevel() -> ThermalLevel {
        #if os(macOS)
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: return .nominal
        case .fair: return .fair
        case .serious: return .serious
        case .critical: return .critical
        @unknown default: return .nominal
        }
        #else
        return .nominal
        #endif
    }

    public static func swapUsage() async -> SwapUsage? {
        let result = await Shell.run("/usr/sbin/sysctl", ["vm.swapusage"], timeout: 5)
        return SwapParser.usage(from: result.stdout)
    }

    public static func topProcesses(limit: Int) async -> [ProcessSample] {
        let result = await Shell.run("/bin/ps", ["-Ac", "-o", "pid=,pcpu=,pmem=,comm=", "-r"], timeout: 5)
        let own = ProcessInfo.processInfo.processIdentifier
        return Array(
            ProcessListParser.samples(from: result.stdout)
                .filter { $0.pid != own }
                .sorted { $0.cpuPercent > $1.cpuPercent }
                .prefix(limit)
        )
    }

    public static func memoryFreePercent() -> Int? {
        sysctlInt32("kern.memorystatus_level").map(Int.init)
    }

    public static func memoryPressure() -> MemoryPressure? {
        sysctlInt32("kern.memorystatus_vm_pressure_level").flatMap(MemoryPressure.init(rawValue:))
    }

    public static func diskSpace() -> (free: Int64?, total: Int64?) {
        let home = FileManager.default.homeDirectoryForCurrentUser
        #if os(macOS)
        let values = try? home.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey])
        return (values?.volumeAvailableCapacityForImportantUsage, values?.volumeTotalCapacity.map(Int64.init))
        #else
        let values = try? home.resourceValues(forKeys: [.volumeAvailableCapacityKey, .volumeTotalCapacityKey])
        return (values?.volumeAvailableCapacity.map(Int64.init), values?.volumeTotalCapacity.map(Int64.init))
        #endif
    }

    private static func sysctlInt32(_ name: String) -> Int32? {
        #if canImport(Darwin)
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname(name, &value, &size, nil, 0) == 0 else { return nil }
        return value
        #else
        return nil
        #endif
    }
}
