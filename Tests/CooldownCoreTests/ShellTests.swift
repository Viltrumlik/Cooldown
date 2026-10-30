import XCTest
@testable import CooldownCore

final class ShellTests: XCTestCase {
    func testCapturesStdoutAndStatus() {
        let result = Shell.runBlocking("/bin/sh", ["-c", "echo hello; exit 3"])
        XCTAssertEqual(result.stdout, "hello\n")
        XCTAssertEqual(result.status, 3)
        XCTAssertFalse(result.succeeded)
    }

    func testLargeOutputOnBothPipesDoesNotDeadlock() {
        // 256 KB on each pipe is far more than a pipe buffer holds.
        let script = "head -c 262144 /dev/zero | tr '\\0' a; head -c 262144 /dev/zero | tr '\\0' b >&2"
        let result = Shell.runBlocking("/bin/sh", ["-c", script], timeout: 20)
        XCTAssertTrue(result.succeeded)
        XCTAssertEqual(result.stdout.count, 262_144)
        XCTAssertEqual(result.stderr.count, 262_144)
    }

    func testTimeoutKillsHungCommand() {
        let started = Date()
        let result = Shell.runBlocking("/bin/sh", ["-c", "sleep 30"], timeout: 0.5)
        XCTAssertFalse(result.succeeded)
        XCTAssertLessThan(Date().timeIntervalSince(started), 10)
    }

    func testMissingExecutable() {
        let result = Shell.runBlocking("/definitely/not/here")
        XCTAssertEqual(result.status, 127)
    }

    func testAsyncRun() async {
        let result = await Shell.run("/bin/sh", ["-c", "printf ok"])
        XCTAssertEqual(result.stdout, "ok")
    }
}
