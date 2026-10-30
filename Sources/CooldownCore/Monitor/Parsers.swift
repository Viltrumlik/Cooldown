import Foundation

// Pure functions that turn command-line output into values.
// Kept separate so they can be unit-tested with captured output.

// MARK: - pmset

public enum PmsetParser {
    /// `CPU_Speed_Limit` from `pmset -g therm`. 100 means full speed; lower
    /// means macOS is slowing the CPU down to control heat. Intel Macs only:
    /// Apple Silicon prints no such line and this returns nil.
    public static func cpuSpeedLimit(from output: String) -> Int? {
        for line in output.split(whereSeparator: \.isNewline) where line.contains("CPU_Speed_Limit") {
            let parts = line.split(separator: "=", maxSplits: 1)
            if parts.count == 2, let value = Int(parts[1].trimmingCharacters(in: .whitespaces)) {
                return value
            }
        }
        return nil
    }
}

// MARK: - Swap

public struct SwapUsage: Sendable, Equatable {
    public let total: Int64
    public let used: Int64
    public let free: Int64

    public init(total: Int64, used: Int64, free: Int64) {
        self.total = total
        self.used = used
        self.free = free
    }
}

public enum SwapParser {
    /// Parses `sysctl vm.swapusage`, e.g.
    /// `vm.swapusage: total = 6144.00M  used = 4922.50M  free = 1221.50M  (encrypted)`
    public static func usage(from output: String) -> SwapUsage? {
        let tokens = output.split(whereSeparator: \.isWhitespace).map(String.init)
        var values: [String: Int64] = [:]
        for index in tokens.indices where index + 2 < tokens.count {
            let key = tokens[index]
            guard ["total", "used", "free"].contains(key), tokens[index + 1] == "=",
                  let bytes = parseSize(tokens[index + 2]) else { continue }
            values[key] = bytes
        }
        guard let total = values["total"], let used = values["used"], let free = values["free"] else {
            return nil
        }
        return SwapUsage(total: total, used: used, free: free)
    }

    /// "6144.00M" -> bytes (binary units, as sysctl prints them).
    static func parseSize(_ text: String) -> Int64? {
        let units: [Character: Double] = [
            "K": 1024, "M": 1024 * 1024, "G": 1024 * 1024 * 1024, "T": 1024 * 1024 * 1024 * 1024
        ]
        guard let last = text.last else { return nil }
        if let multiplier = units[Character(last.uppercased())] {
            guard let number = Double(text.dropLast()) else { return nil }
            return Int64((number * multiplier).rounded())
        }
        return Double(text).map { Int64($0.rounded()) }
    }
}

// MARK: - ps / pgrep

public struct ProcessSample: Sendable, Equatable, Identifiable {
    public let pid: Int32
    public let cpuPercent: Double
    public let memoryPercent: Double
    public let name: String

    public var id: Int32 { pid }

    public init(pid: Int32, cpuPercent: Double, memoryPercent: Double, name: String) {
        self.pid = pid
        self.cpuPercent = cpuPercent
        self.memoryPercent = memoryPercent
        self.name = name
    }

    /// A human hint for cryptic process names.
    public var hint: String? { ProcessListParser.hint(for: name) }
}

public enum ProcessListParser {
    /// Parses `ps -Ac -o pid=,pcpu=,pmem=,comm=`. Names may contain spaces
    /// ("Claude Helper (Renderer)"), so the name is everything after the
    /// third column.
    public static func samples(from output: String) -> [ProcessSample] {
        output.split(whereSeparator: \.isNewline).compactMap { line in
            let fields = splitFields(String(line), count: 4)
            guard fields.count == 4,
                  let pid = Int32(fields[0]),
                  let cpu = Double(fields[1]),
                  let mem = Double(fields[2]) else { return nil }
            return ProcessSample(pid: pid, cpuPercent: cpu, memoryPercent: mem, name: fields[3])
        }
    }

    /// One PID per line, as printed by `pgrep`.
    public static func pids(from output: String) -> [Int32] {
        output.split(whereSeparator: \.isNewline).compactMap {
            Int32($0.trimmingCharacters(in: .whitespaces))
        }
    }

    public static func hint(for name: String) -> String? {
        switch name {
        case "SimMetalHost", "launchd_sim", "com.apple.CoreSimulator.CoreSimulatorService":
            return "iOS Simulator"
        case "kernel_task":
            return "macOS cooling the CPU; high means overheating"
        case "mds", "mds_stores", "mdworker", "mdworker_shared":
            return "Spotlight indexing"
        case "WindowServer":
            return "Draws the screen"
        case "qemu-system-aarch64", "qemu-system-x86_64":
            return "Android Emulator"
        case "java":
            return "Java (Gradle / Android Studio?)"
        case "node":
            return "Node.js"
        default:
            return nil
        }
    }

    /// Splits on runs of whitespace into at most `count` fields; the last
    /// field keeps its inner spaces.
    static func splitFields(_ line: String, count: Int) -> [String] {
        var fields: [String] = []
        var rest = Substring(line)
        while fields.count < count - 1 {
            rest = rest.drop(while: \.isWhitespace)
            guard let end = rest.firstIndex(where: \.isWhitespace) else { break }
            fields.append(String(rest[..<end]))
            rest = rest[end...]
        }
        let last = rest.trimmingCharacters(in: .whitespaces)
        if !last.isEmpty { fields.append(last) }
        return fields
    }
}

// MARK: - simctl

public struct SimulatorDevice: Decodable, Sendable, Equatable {
    public let udid: String
    public let name: String
    public let state: String
    /// Missing in very old Xcode versions; treated as available.
    public let isAvailable: Bool?
}

public enum SimctlParser {
    private struct Root: Decodable {
        let devices: [String: [SimulatorDevice]]
    }

    /// Parses `xcrun simctl list devices -j`.
    public static func devices(from data: Data) throws -> [SimulatorDevice] {
        try JSONDecoder().decode(Root.self, from: data).devices.values.flatMap { $0 }
    }
}
