import XCTest
@testable import CooldownCore

final class ParsersTests: XCTestCase {

    // MARK: pmset

    func testCPUSpeedLimitOnThrottledIntelMac() {
        let output = """
        Note: No thermal warning level has been recorded
        Note: No performance warning level has been recorded
        2026-10-30 22:52:45 +0500 CPU Power notify
        \tCPU_Scheduler_Limit \t= 100
        \tCPU_Available_CPUs \t= 16
        \tCPU_Speed_Limit \t= 52
        """
        XCTAssertEqual(PmsetParser.cpuSpeedLimit(from: output), 52)
    }

    func testCPUSpeedLimitMissingOnAppleSilicon() {
        let output = """
        Note: No thermal warning level has been recorded
        Note: No performance warning level has been recorded
        Note: No CPU power status has been recorded
        """
        XCTAssertNil(PmsetParser.cpuSpeedLimit(from: output))
    }

    // MARK: swap

    func testSwapUsage() {
        let output = "vm.swapusage: total = 6144.00M  used = 4922.50M  free = 1221.50M  (encrypted)"
        let usage = SwapParser.usage(from: output)
        XCTAssertEqual(usage?.total, 6144 * 1_048_576)
        XCTAssertEqual(usage?.used, 5_161_615_360)
        XCTAssertEqual(usage?.free, 1_280_835_584)
    }

    func testSwapUsageWithGigabytesAndNoSwap() {
        XCTAssertEqual(SwapParser.usage(from: "vm.swapusage: total = 2.00G  used = 0.00M  free = 2.00G")?.total, 2 * 1_073_741_824)
        XCTAssertNil(SwapParser.usage(from: "garbage"))
    }

    // MARK: ps

    func testProcessSamplesKeepSpacesInNames() {
        let output = """
          612  28.3  0.2 backboardd
          977  22.9  0.2 SimMetalHost
          401  13.1  0.3 Cloudflare WARP
         1203   0.0  4.1 Claude Helper (Renderer)
        """
        let samples = ProcessListParser.samples(from: output)
        XCTAssertEqual(samples.count, 4)
        XCTAssertEqual(samples[0], ProcessSample(pid: 612, cpuPercent: 28.3, memoryPercent: 0.2, name: "backboardd"))
        XCTAssertEqual(samples[2].name, "Cloudflare WARP")
        XCTAssertEqual(samples[3].name, "Claude Helper (Renderer)")
        XCTAssertEqual(samples[3].memoryPercent, 4.1)
        XCTAssertEqual(samples[1].hint, "iOS Simulator")
    }

    func testProcessSamplesSkipMalformedLines() {
        XCTAssertTrue(ProcessListParser.samples(from: "\n  abc def\n 12 x y z\n").isEmpty)
    }

    func testPIDs() {
        XCTAssertEqual(ProcessListParser.pids(from: "123\n 456 \n\nnope\n"), [123, 456])
    }

    // MARK: simctl

    func testSimctlDevices() throws {
        let json = """
        {
          "devices" : {
            "com.apple.CoreSimulator.SimRuntime.iOS-18-2" : [
              { "udid" : "A1", "name" : "iPhone 16", "state" : "Booted", "isAvailable" : true },
              { "udid" : "A2", "name" : "iPhone 16 Pro", "state" : "Shutdown", "isAvailable" : true }
            ],
            "com.apple.CoreSimulator.SimRuntime.iOS-16-0" : [
              { "udid" : "B1", "name" : "iPhone 14", "state" : "Shutdown", "isAvailable" : false,
                "availabilityError" : "runtime profile not found" }
            ]
          }
        }
        """
        let devices = try SimctlParser.devices(from: Data(json.utf8))
        XCTAssertEqual(devices.count, 3)
        XCTAssertEqual(devices.filter { $0.state == "Booted" }.map(\.udid), ["A1"])
        XCTAssertEqual(devices.filter { $0.isAvailable == false }.map(\.udid), ["B1"])
    }

    // MARK: scan results

    func testScanResultHasWork() {
        XCTAssertTrue(ScanResult.files(bytes: 10, items: 1).hasWork)
        XCTAssertTrue(ScanResult.processes(count: 2).hasWork)
        XCTAssertFalse(ScanResult.empty.hasWork)
        XCTAssertFalse(ScanResult.notApplicable.hasWork)
        XCTAssertFalse(ScanResult.unavailable(reason: "x").hasWork)
    }

    func testCatalogIDsAreUnique() {
        let ids = Catalog.defaultTargets().map(\.info.id)
        XCTAssertEqual(ids.count, Set(ids).count)
    }

    func testCautionTargetsAreOffByDefault() {
        for target in Catalog.defaultTargets() where target.info.risk == .caution {
            XCTAssertFalse(target.info.enabledByDefault, "\(target.info.id) is risky and must be opt-in")
        }
    }
}
