import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// Runs command-line tools off the main thread, with a timeout, and without
/// the classic pipe-buffer deadlock.
public enum Shell {
    public struct Result: Sendable, Equatable {
        public let status: Int32
        public let stdout: String
        public let stderr: String

        public init(status: Int32, stdout: String, stderr: String) {
            self.status = status
            self.stdout = stdout
            self.stderr = stderr
        }

        public var succeeded: Bool { status == 0 }
    }

    /// Apps launched from Finder get a minimal PATH; Homebrew and friends
    /// live elsewhere.
    public static let searchPath = [
        "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin"
    ].joined(separator: ":")

    /// Absolute path of a tool on `searchPath`, if installed.
    public static func which(_ name: String) -> String? {
        for directory in searchPath.split(separator: ":") {
            let candidate = "\(directory)/\(name)"
            if FileManager.default.isExecutableFile(atPath: candidate) { return candidate }
        }
        return nil
    }

    public static func run(
        _ executable: String,
        _ arguments: [String] = [],
        timeout: TimeInterval = 60
    ) async -> Result {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: runBlocking(executable, arguments, timeout: timeout))
            }
        }
    }

    public static func runBlocking(
        _ executable: String,
        _ arguments: [String] = [],
        timeout: TimeInterval = 60
    ) -> Result {
        guard FileManager.default.isExecutableFile(atPath: executable) else {
            return Result(status: 127, stdout: "", stderr: "\(executable) not found")
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = searchPath
        process.environment = environment
        process.standardInput = FileHandle.nullDevice

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        do {
            try process.run()
        } catch {
            return Result(status: -1, stdout: "", stderr: error.localizedDescription)
        }

        // Drain both pipes concurrently: a tool that writes a lot to one of
        // them would otherwise block forever on a full pipe buffer.
        let output = Collected()
        let readers = DispatchGroup()
        for (pipe, stream) in [(outPipe, Collected.Stream.out), (errPipe, Collected.Stream.err)] {
            readers.enter()
            DispatchQueue.global(qos: .utility).async {
                output.set(pipe.fileHandleForReading.readDataToEndOfFile(), for: stream)
                readers.leave()
            }
        }

        let pid = process.processIdentifier
        let watchdog = DispatchWorkItem {
            guard process.isRunning else { return }
            terminateTree(pid, signal: SIGTERM)
            DispatchQueue.global().asyncAfter(deadline: .now() + 2) {
                if process.isRunning { terminateTree(pid, signal: SIGKILL) }
            }
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: watchdog)

        process.waitUntilExit()
        watchdog.cancel()
        // A grandchild could keep a pipe open; don't wait on it forever.
        _ = readers.wait(timeout: .now() + 5)

        return Result(
            status: process.terminationStatus,
            stdout: output.string(.out),
            stderr: output.string(.err)
        )
    }

    /// Signals the direct children first (a `sh -c` wrapper's child would
    /// otherwise survive and keep the pipes open), then the process itself.
    private static func terminateTree(_ pid: Int32, signal: Int32) {
        let pkill = Process()
        pkill.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
        pkill.arguments = ["-\(signal)", "-P", String(pid)]
        pkill.standardOutput = FileHandle.nullDevice
        pkill.standardError = FileHandle.nullDevice
        if (try? pkill.run()) != nil {
            pkill.waitUntilExit()
        }
        kill(pid, signal)
    }

    private final class Collected: @unchecked Sendable {
        enum Stream { case out, err }

        private let lock = NSLock()
        private var storage: [Stream: Data] = [:]

        func set(_ data: Data, for stream: Stream) {
            lock.lock()
            storage[stream] = data
            lock.unlock()
        }

        func string(_ stream: Stream) -> String {
            lock.lock()
            defer { lock.unlock() }
            return String(decoding: storage[stream] ?? Data(), as: UTF8.self)
        }
    }
}
