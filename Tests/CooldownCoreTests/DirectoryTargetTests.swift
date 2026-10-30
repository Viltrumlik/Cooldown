import XCTest
@testable import CooldownCore

final class DirectoryTargetTests: XCTestCase {
    private var sandbox: URL!
    private var home: URL!

    override func setUpWithError() throws {
        sandbox = FileManager.default.temporaryDirectory.appendingPathComponent("cooldown-dir-\(UUID().uuidString)")
        home = sandbox.appendingPathComponent("home")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: sandbox)
    }

    private func info(_ id: String = "test") -> TargetInfo {
        TargetInfo(id: id, title: "Test", detail: "", group: .system, risk: .safe, enabledByDefault: true)
    }

    private func write(_ relative: String, bytes: Int = 64 * 1024) throws {
        let url = home.appendingPathComponent(relative)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 7, count: bytes).write(to: url)
    }

    private func exists(_ relative: String) -> Bool {
        FileManager.default.fileExists(atPath: home.appendingPathComponent(relative).path)
    }

    func testScanAndCleanEmptiesFolderButKeepsIt() async throws {
        try write("cache/a.bin")
        try write("cache/nested/b.bin")
        let target = DirectoryTarget(info: info(), roots: ["cache"], home: home)

        let scan = await target.scan()
        guard case let .files(bytes, items) = scan else { return XCTFail("expected files, got \(scan)") }
        XCTAssertEqual(items, 2)
        XCTAssertGreaterThan(bytes, 0)

        let outcome = await target.clean()
        XCTAssertTrue(outcome.succeeded, "\(outcome.errors)")
        XCTAssertEqual(outcome.freedBytes, bytes)
        XCTAssertTrue(exists("cache"), "the root folder itself must survive")
        XCTAssertFalse(exists("cache/a.bin"))
        XCTAssertFalse(exists("cache/nested"))

        let after = await target.scan()
        XCTAssertEqual(after, .empty)
    }

    func testMissingFolderIsNotApplicable() async {
        let target = DirectoryTarget(info: info(), roots: ["does/not/exist"], home: home)
        let scan = await target.scan()
        XCTAssertEqual(scan, .notApplicable)
    }

    func testExcludedNamesAndPrefixesAreKept() async throws {
        try write("Library/Caches/com.apple.Safari/x")
        try write("Library/Caches/Homebrew/y")
        try write("Library/Caches/com.example.app/z")
        let target = DirectoryTarget(
            info: info(),
            roots: ["Library/Caches"],
            excludingNames: ["Homebrew"],
            excludingPrefixes: ["com.apple."],
            home: home
        )

        _ = await target.clean()

        XCTAssertTrue(exists("Library/Caches/com.apple.Safari/x"))
        XCTAssertTrue(exists("Library/Caches/Homebrew/y"))
        XCTAssertFalse(exists("Library/Caches/com.example.app"))
    }

    func testSymlinkInsideCacheIsRemovedWithoutTouchingItsTarget() async throws {
        try write("precious/keep.txt")
        try FileManager.default.createDirectory(at: home.appendingPathComponent("cache"), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            at: home.appendingPathComponent("cache/link"),
            withDestinationURL: home.appendingPathComponent("precious")
        )
        let target = DirectoryTarget(info: info(), roots: ["cache"], home: home)

        _ = await target.clean()

        XCTAssertTrue(exists("precious/keep.txt"), "files behind a symlink must never be deleted")
        XCTAssertNil(try? FileManager.default.destinationOfSymbolicLink(atPath: home.appendingPathComponent("cache/link").path))
    }

    func testProtectedRootIsRefusedAndUntouched() async throws {
        try write("Documents/thesis.docx")
        let target = DirectoryTarget(info: info(), roots: ["Documents"], home: home)

        let scan = await target.scan()
        guard case .unavailable = scan else { return XCTFail("expected unavailable, got \(scan)") }

        let outcome = await target.clean()
        XCTAssertFalse(outcome.succeeded)
        XCTAssertEqual(outcome.freedBytes, 0)
        XCTAssertTrue(exists("Documents/thesis.docx"))
    }

    func testSymlinkedRootPointingOutsideHomeIsRefused() async throws {
        let outside = sandbox.appendingPathComponent("outside")
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        try Data([1, 2, 3]).write(to: outside.appendingPathComponent("system-file"))
        try FileManager.default.createSymbolicLink(at: home.appendingPathComponent(".npm"), withDestinationURL: outside)
        let target = DirectoryTarget(info: info(), roots: [".npm"], home: home)

        _ = await target.clean()

        XCTAssertTrue(FileManager.default.fileExists(atPath: outside.appendingPathComponent("system-file").path))
    }
}
