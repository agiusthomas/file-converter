import XCTest
@testable import ConverterCore

final class EngineLifecycleTests: XCTestCase {
    var root: URL!
    override func setUpWithError() throws { root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString); try FileManager.default.createDirectory(at:root,withIntermediateDirectories:false) }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at:root) }
    func pack() throws -> InstalledEnginePack {
        let url = root.appendingPathComponent("media-0.1.2.bundle")
        try FileManager.default.createDirectory(at:url,withIntermediateDirectories:false)
        try Data("owned lifecycle fixture, never executable".utf8).write(to:url.appendingPathComponent("data"))
        let manifest = EnginePackManifest(schemaVersion:1,id:"media",version:"0.1.2",minimumAppVersion:"0.2.1",minimumOSVersion:"13.0",architectures:["arm64"],tools:[:],files:[:],licenses:[],installedBytes:1,engineVersions:[:])
        return InstalledEnginePack(location:url,manifest:manifest)
    }
    func testRemovalWaitsForLiveSnapshotAndReclaimsAfterRelease() throws {
        let pack = try pack()
        try Data(pack.location.lastPathComponent.utf8).write(to:root.appendingPathComponent("media.current"))
        var lease: EnginePackLease? = try EnginePackLease(packs:[pack])
        weak var observer = lease
        XCTAssertNotNil(observer)
        try EnginePacks.requestRemoval("media",root:root)
        XCTAssertFalse(FileManager.default.fileExists(atPath:root.appendingPathComponent("media.current").path))
        XCTAssertEqual(try EnginePacks.collectRemovals(root:root),["media"])
        XCTAssertTrue(FileManager.default.fileExists(atPath:pack.location.path))
        lease = nil
        XCTAssertNil(observer)
        XCTAssertTrue(try EnginePacks.collectRemovals(root:root).isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath:pack.location.path))
    }
    func testCorruptLeasePreventsRemoval() throws {
        let pack = try pack()
        let leases = root.appendingPathComponent(".leases")
        try FileManager.default.createDirectory(at:leases,withIntermediateDirectories:false)
        let file = leases.appendingPathComponent(UUID().uuidString + ".json")
        try Data("interrupted lease write".utf8).write(to:file)
        try EnginePacks.requestRemoval("media",root:root)
        XCTAssertEqual(try EnginePacks.collectRemovals(root:root),["media"])
        XCTAssertTrue(FileManager.default.fileExists(atPath:pack.location.path))
        try JSONEncoder().encode(EnginePackLease.Record(pid:ProcessInfo.processInfo.processIdentifier,bundles:[])).write(to:file,options:.atomic)
        XCTAssertEqual(try EnginePacks.collectRemovals(root:root),["media"])
        XCTAssertTrue(FileManager.default.fileExists(atPath:pack.location.path))
    }
    func testRemovalDoesNotTouchUnrelatedFilesOrFollowSymlinks() throws {
        let unrelated = root.appendingPathComponent("original.txt")
        try Data("original".utf8).write(to:unrelated)
        let link = root.appendingPathComponent("media-0.1.2.bundle")
        try FileManager.default.createSymbolicLink(at:link,withDestinationURL:unrelated)
        try EnginePacks.requestRemoval("media",root:root)
        XCTAssertThrowsError(try EnginePacks.collectRemovals(root:root))
        XCTAssertEqual(try String(contentsOf:unrelated,encoding:.utf8),"original")
        XCTAssertThrowsError(try EnginePacks.requestRemoval("../media",root:root))
    }
    func testCatalogBoundsCompatibilityAndTrust() async throws {
        var entry = EngineDownload(id:"media",version:"0.1.2",url:URL(string:"https://example.com/runtime.zip")!,sha256:String(repeating:"a",count:64),downloadBytes:100)
        XCTAssertTrue(EnginePacks.validDownload(entry))
        entry.minimumAppVersion = "999.0"
        XCTAssertNotNil(EnginePacks.incompatibility(entry))
        entry.minimumAppVersion = "0.2.0"; entry.architectures = ["unsupported"]
        XCTAssertNotNil(EnginePacks.incompatibility(entry))
        entry.url = URL(string:"http://example.com/runtime.zip")!
        XCTAssertFalse(EnginePacks.validDownload(entry))
        entry.url = URL(string:"https://example.com/runtime.zip")!; entry.downloadBytes = 4*1024*1024*1024+1
        XCTAssertFalse(EnginePacks.validDownload(entry))
        entry.downloadBytes = 100; entry.sha256 = "wrong"
        XCTAssertFalse(EnginePacks.validDownload(entry))
        entry.sha256 = String(repeating:"a",count:64); entry.architectures = ["arm64"]
        do { _ = try await EnginePacks.download(entry,root:root); XCTFail("An entry outside the sealed catalog was accepted") }
        catch { XCTAssertTrue(error.localizedDescription.contains("trusted catalog")) }
    }
    func testPackRootSymlinkIsRejectedBeforeSignatureLookup() throws {
        let target = root.appendingPathComponent("original")
        try FileManager.default.createDirectory(at:target,withIntermediateDirectories:false)
        let link = root.appendingPathComponent("linked.bundle")
        try FileManager.default.createSymbolicLink(at:link,withDestinationURL:target)
        XCTAssertThrowsError(try EnginePacks.verify(link,trustedTeam:"QJ75C25V8L")) { error in
            XCTAssertTrue(error.localizedDescription.contains("regular engine bundle"))
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath:target.path))
    }
    func testLeaseDirectorySymlinkCannotDeleteAnOutsideFile() throws {
        let pack = try pack()
        let originals = root.appendingPathComponent("originals")
        try FileManager.default.createDirectory(at:originals,withIntermediateDirectories:false)
        let file = originals.appendingPathComponent(UUID().uuidString + ".json")
        let data = try JSONEncoder().encode(EnginePackLease.Record(pid:Int32.max,bundles:["media-0.1.2.bundle"]))
        try data.write(to:file)
        try FileManager.default.createSymbolicLink(at:root.appendingPathComponent(".leases"),withDestinationURL:originals)
        XCTAssertThrowsError(try EnginePackLease(packs:[pack]))
        try EnginePacks.requestRemoval("media",root:root)
        XCTAssertEqual(try EnginePacks.collectRemovals(root:root),["media"])
        XCTAssertEqual(try Data(contentsOf:file),data)
    }
}
