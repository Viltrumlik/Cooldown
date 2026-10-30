import XCTest
@testable import CooldownCore

final class PathGuardTests: XCTestCase {
    private var sandbox: URL!
    private var home: URL!
    private var outside: URL!
    private var pathGuard: PathGuard!

    override func setUpWithError() throws {
        sandbox = FileManager.default.temporaryDirectory.appendingPathComponent("cooldown-guard-\(UUID().uuidString)")
        home = sandbox.appendingPathComponent("home")
        outside = sandbox.appendingPathComponent("outside")
        // Folders must exist: on macOS, /var/folders resolves differently for
        // paths that don't exist yet.
        let folders = [
            home!, outside!,
            home.appendingPathComponent("Documents"),
            home.appendingPathComponent("Library/Application Support"),
            home.appendingPathComponent("Library/Caches/pip")
        ]
        for folder in folders {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        pathGuard = PathGuard(home: home)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: sandbox)
    }

    func testAcceptsCacheFolderInsideHome() throws {
        let root = pathGuard.home.appendingPathComponent("Library/Caches/pip")
        XCTAssertNoThrow(try pathGuard.validateRoot(root))
    }

    func testRefusesHomeItself() {
        XCTAssertThrowsError(try pathGuard.validateRoot(home))
    }

    func testRefusesProtectedFolders() {
        for relative in ["Documents", "Library", "library", "Library/Application Support"] {
            XCTAssertThrowsError(try pathGuard.validateRoot(home.appendingPathComponent(relative)), relative) { error in
                guard case PathGuard.Violation.protectedFolder = error else {
                    return XCTFail("\(relative): expected protectedFolder, got \(error)")
                }
            }
        }
    }

    func testRefusesFolderOutsideHome() {
        XCTAssertThrowsError(try pathGuard.validateRoot(outside)) { error in
            guard case PathGuard.Violation.outsideHome = error else { return XCTFail("got \(error)") }
        }
    }

    func testRefusesDotDotEscape() {
        let sneaky = home.appendingPathComponent("Library/Caches/../../../outside")
        XCTAssertThrowsError(try pathGuard.validateRoot(sneaky))
    }

    func testRefusesSymlinkedRootPointingOutsideHome() throws {
        let link = home.appendingPathComponent(".npm")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)
        XCTAssertThrowsError(try pathGuard.validateRoot(link)) { error in
            guard case PathGuard.Violation.outsideHome = error else { return XCTFail("got \(error)") }
        }
    }

    func testChildMustBeDirectChildOfRoot() throws {
        let root = try pathGuard.validateRoot(home.appendingPathComponent("Library/Caches/pip"))
        XCTAssertNoThrow(try pathGuard.validateChild(root.appendingPathComponent("wheels"), ofValidatedRoot: root))
        XCTAssertThrowsError(try pathGuard.validateChild(root.appendingPathComponent("a/b"), ofValidatedRoot: root))
        XCTAssertThrowsError(try pathGuard.validateChild(root.appendingPathComponent("../../Documents"), ofValidatedRoot: root))
    }
}
