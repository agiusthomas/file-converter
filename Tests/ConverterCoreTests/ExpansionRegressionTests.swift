import XCTest
import Foundation
import CoreGraphics
import ImageIO
@testable import ConverterCore

final class ExpansionRegressionTests: XCTestCase {
    var root: URL!
    override func setUpWithError() throws { root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString); try FileManager.default.createDirectory(at:root,withIntermediateDirectories:false) }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at:root) }
    func image(in directory: URL) throws -> URL {
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        let context = try XCTUnwrap(CGContext(data:nil,width:20,height:10,bitsPerComponent:8,bytesPerRow:80,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue))
        context.clear(CGRect(x:0,y:0,width:20,height:10)); context.setFillColor(CGColor(red:0.2,green:0.6,blue:1,alpha:0.5)); context.fill(CGRect(x:0,y:0,width:10,height:10))
        let url = directory.appendingPathComponent("sample.png"); try PDFEngine.saveImage(XCTUnwrap(context.makeImage()),to:url,format:.png,quality:1); return url
    }
    func testWebPAlphaIsActuallyPreserved() async throws {
        let input = try image(in:root), engine = NativeEngine()
        let result = try await engine.execute(.init(inputs:[input],action:.imageConvert,profiles:[.init("webp","WEBP","webp")]),in:root.appendingPathComponent("out"))
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(result.outputs[0].url as CFURL,nil)), decoded = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source,0,nil))
        let context = try XCTUnwrap(CGContext(data:nil,width:20,height:10,bitsPerComponent:8,bytesPerRow:80,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(decoded,in:CGRect(x:0,y:0,width:20,height:10))
        let bytes = try XCTUnwrap(context.data).assumingMemoryBound(to:UInt8.self)
        XCTAssertEqual(bytes[(5*20+15)*4+3],0); XCTAssertEqual(Int(bytes[(5*20+5)*4+3]),128,accuracy:2)
    }
    func testHTMLBoundaryDropsResourcesAndExecutableAttributes() throws {
        let input = #"<body onload="alert(1)"><h1>Hello</h1><script>bad()</script><img src="https://example.invalid/a"><a href="file:///etc/passwd">Keep text</a><iframe src="https://example.invalid"></iframe><p style="background:url(https://example.invalid)">End &amp; more</p></body>"#
        let output = try HTMLSanitizer.staticDocument(input)
        XCTAssertTrue(output.contains("<h1>Hello</h1>")); XCTAssertTrue(output.contains("<a>Keep text</a>")); XCTAssertTrue(output.contains("End &amp; more"))
        for unsafe in ["src=","href=","onload", "background", "bad()", "<script", "<img", "<iframe", "example.invalid", "file://"] { XCTAssertFalse(output.contains(unsafe),unsafe) }
        let malformed = try HTMLSanitizer.staticDocument(#"<script><p onclick="x">Visible</p><img src="x"><!-- <iframe src="https://evil"> -->"#)
        XCTAssertFalse(malformed.contains("onclick")); XCTAssertFalse(malformed.contains("src=")); XCTAssertFalse(malformed.contains("<script"))
    }
    func testCodecClaimsRequireBothEncoderAndMuxer() {
        let build = MediaBuildCapabilities.parse(encoders:"Encoders:\n A....D libmp3lame MP3\n A....D aac AAC\n V....D libvpx-vp9 VP9\n A....D libopus Opus",muxers:"Formats:\n E mp3 MPEG\n E webm WebM")
        XCTAssertTrue(build.supports(.init("mp3","MP3","mp3",audioCodec:"libmp3lame")))
        XCTAssertTrue(build.supports(.init("webm","WebM","webm",videoCodec:"libvpx-vp9",audioCodec:"libopus")))
        XCTAssertFalse(build.supports(ActionCatalog.m4a)); XCTAssertFalse(build.supports(ActionCatalog.mp4))
    }
    func testNamingAndRelativeFolderPublication() async throws {
        let source = root.appendingPathComponent("source"), nested = source.appendingPathComponent("Folder/Child"), destination = root.appendingPathComponent("results")
        let input = try image(in:nested); try FileManager.default.createDirectory(at:destination,withIntermediateDirectories:false)
        let coordinator = JobCoordinator(transport:InProcessWorkerTransport(),journal:root.appendingPathComponent("jobs"))
        var options = OperationOptions(); options.filenameTemplate = "{index}-{name}-{format}"; options.sequence = 4
        var request = OperationRequest(inputs:[input],action:.imageConvert,profiles:[ActionCatalog.jpg],options:options,destination:destination); request.relativeSourceRoot = source
        let result = try await coordinator.run(request)
        XCTAssertEqual(result.outputs[0].url.path,destination.appendingPathComponent("Folder/Child/4-sample-jpg.jpg").path)
        XCTAssertEqual(result.outputs[0].sources,[input]); XCTAssertTrue(FileManager.default.fileExists(atPath:input.path))
        XCTAssertThrowsError(try NamingPolicy.stem(template:"../{name}",source:input,profile:ActionCatalog.jpg,index:1))
    }
    func testRecoveryCleansNestedStageWithoutTouchingOriginals() async throws {
        let source = root.appendingPathComponent("source"), destination = root.appendingPathComponent("results"), input = try image(in:source.appendingPathComponent("Nested"))
        var request = OperationRequest(inputs:[input],action:.imageConvert,profiles:[ActionCatalog.jpg],destination:destination); request.relativeSourceRoot = source
        let stage = destination.appendingPathComponent("Nested/.file-converter-\(request.id.uuidString)")
        try FileManager.default.createDirectory(at:stage,withIntermediateDirectories:true)
        var record = JobRecord(request:request,state:.publishing); record.ownerPID = Int32.max; record.stageDirectory = stage
        let journal = root.appendingPathComponent("jobs"); try FileManager.default.createDirectory(at:journal,withIntermediateDirectories:false)
        try JSONEncoder().encode(record).write(to:journal.appendingPathComponent(request.id.uuidString+".json"))
        let records = try await JobCoordinator(transport:InProcessWorkerTransport(),journal:journal).records(recoverInterrupted:true)
        XCTAssertEqual(records[0].state,.interrupted); XCTAssertFalse(FileManager.default.fileExists(atPath:stage.path)); XCTAssertTrue(FileManager.default.fileExists(atPath:input.path))
    }
    func testRecipeHistoryRetainsOriginalLineageAndNoTemporaryJobs() async throws {
        let input = try image(in:root), jobs = JobCoordinator(transport:InProcessWorkerTransport(),journal:root.appendingPathComponent("jobs"))
        var resized = OperationOptions(); resized.maximumDimension = 10
        let recipe = Recipe(name:"Resize then share",steps:[.init(action:.imageConvert,profiles:[ActionCatalog.png],options:resized),.init(action:.imageConvert,profiles:[ActionCatalog.jpg],export:true),.init(action:.imageConvert,profiles:[.init("webp","WEBP","webp")],export:true)])
        let result = try await jobs.run(recipe,inputs:[input]); XCTAssertEqual(result.outputs.count,2)
        XCTAssertEqual(result.outputs.map(\.width),[10,10]); XCTAssertTrue(result.outputs.allSatisfy { $0.sources == [input] })
        let records = try await jobs.records(); XCTAssertEqual(records.count,1); XCTAssertEqual(records[0].request.inputs,[input]); XCTAssertEqual(records[0].recipe?.name,recipe.name); XCTAssertEqual(records[0].completedRecipeExports,[1,2])
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath:root.path).contains(where:{$0.hasPrefix(".file-converter-")}))
        let retry = try await jobs.run(recipe,inputs:[input],skippingExports:[1]); XCTAssertEqual(retry.outputs.count,1); XCTAssertEqual(retry.outputs[0].format,"webp")
    }
    func testNestedFolderArchiveAndSnapshotKeepRelativePaths() throws {
        let source = root.appendingPathComponent("A/Files"), nested = source.appendingPathComponent("B/Inner")
        let input = try image(in:nested), snapshot = root.appendingPathComponent("snapshot")
        try InputSnapshot.copy(source,to:snapshot)
        XCTAssertEqual(try Data(contentsOf:snapshot.appendingPathComponent("B/Inner/sample.png")),try Data(contentsOf:input))
        let archive = root.appendingPathComponent("nested.zip"); try ArchiveEngine.create([source],to:archive,format:"zip")
        let members = try ArchiveEngine.list(archive).map(\.name)
        XCTAssertTrue(members.contains("Files/B/Inner/sample.png")); XCTAssertFalse(members.contains(where:{$0.contains("Files/Files/")}))
        let extracted = root.appendingPathComponent("extracted"); _ = try ArchiveEngine.extract(archive,to:extracted)
        XCTAssertEqual(try Data(contentsOf:extracted.appendingPathComponent("Files/B/Inner/sample.png")),try Data(contentsOf:input))
    }
    func testPendingSubmissionIsPersistedAndCanBeCancelledBeforeExecution() async throws {
        let input = try image(in:root), jobs = JobCoordinator(transport:InProcessWorkerTransport(),journal:root.appendingPathComponent("jobs"))
        let request = OperationRequest(inputs:[input],action:.imageConvert,profiles:[ActionCatalog.jpg])
        try await jobs.submit(request)
        var records = try await jobs.records(); XCTAssertEqual(records.count,1); XCTAssertEqual(records[0].state,.queued)
        try await jobs.cancelSubmitted(request.id); records = try await jobs.records(); XCTAssertEqual(records[0].state,.cancelled)
        XCTAssertFalse(FileManager.default.fileExists(atPath:root.appendingPathComponent("sample.jpg").path))
    }
    func testOpenDocumentFamilyComesFromEmbeddedMimetype() async throws {
        let mime = root.appendingPathComponent("mimetype"), content = root.appendingPathComponent("content.xml")
        try Data("application/vnd.oasis.opendocument.spreadsheet".utf8).write(to:mime); try Data("<generated-fixture/>".utf8).write(to:content)
        let disguised = root.appendingPathComponent("misleading.docx"); try ArchiveEngine.create([mime,content],to:disguised,format:"zip")
        let asset = try await AssetInspector.inspect(disguised); XCTAssertEqual(asset.family,.spreadsheet); XCTAssertEqual(asset.format,"ods")
        XCTAssertEqual(try ArchiveEngine.readMember("mimetype",from:disguised),try Data(contentsOf:mime))
        XCTAssertThrowsError(try ArchiveEngine.readMember("content.xml",from:disguised,limit:2))
    }
    func testWorkerExitWithoutManifestCannotReportSuccess() async throws {
        let input = try image(in:root), before = try FileDigest.sha256(input)
        let jobs = JobCoordinator(transport:ProcessWorkerTransport(executable:URL(fileURLWithPath:"/usr/bin/true")),journal:root.appendingPathComponent("jobs"))
        do { _ = try await jobs.run(.init(inputs:[input],action:.imageConvert,profiles:[ActionCatalog.jpg])); XCTFail("Exit without a manifest reported success") } catch {}
        let records = try await jobs.records(); XCTAssertEqual(records[0].state,.failed); XCTAssertNil(records[0].manifest); XCTAssertEqual(try FileDigest.sha256(input),before)
    }
    func testPartialPublicationKeepsAnAccurateSavedManifest() async throws {
        let input = try image(in:root), name = String(repeating:"x",count:251)+".jpg"
        let collision = root.appendingPathComponent(name); try Data("existing".utf8).write(to:collision)
        let jobs = JobCoordinator(transport:PartialPublicationTransport(longName:name),journal:root.appendingPathComponent("jobs"))
        do { _ = try await jobs.run(.init(inputs:[input],action:.imageConvert,profiles:[ActionCatalog.png,ActionCatalog.jpg])); XCTFail("Expected the second publication to fail") } catch {}
        let records = try await jobs.records(); let record = try XCTUnwrap(records.first)
        XCTAssertEqual(record.state,.failed); XCTAssertEqual(record.manifest?.outputs.count,1)
        XCTAssertEqual(record.manifest?.outputs.first?.url.lastPathComponent,"first.png")
        XCTAssertTrue(FileManager.default.fileExists(atPath:root.appendingPathComponent("first.png").path)); XCTAssertEqual(try Data(contentsOf:collision),Data("existing".utf8))
    }
    func testMixedUnknownFilesStayVisibleAndCanBeArchived() async throws {
        let picture = try image(in:root), empty = root.appendingPathComponent("empty.bin"); try Data().write(to:empty)
        let jobs = JobCoordinator(transport:InProcessWorkerTransport(),journal:root.appendingPathComponent("jobs"))
        let assets = try await jobs.inspect([picture,empty]); XCTAssertEqual(assets.count,2); XCTAssertEqual(assets[1].family,.unknown)
        let actions = ActionCatalog.actions(for:assets,installedOnly:true); XCTAssertEqual(actions.map(\.id),[.archiveCreate])
        let archive = try await jobs.run(.init(inputs:[picture,empty],action:.archiveCreate,profiles:[.init("zip","ZIP","zip")]))
        XCTAssertEqual(try ArchiveEngine.list(archive.outputs[0].url).count,2)
        var unsupported = AssetDescriptor(source:root.appendingPathComponent("media"),family:.video,format:"unavailable-media",byteCount:10); unsupported.supportedProfiles = []
        XCTAssertEqual(ActionCatalog.actions(for:[unsupported]).first(where:{$0.id == .mediaConvert})?.available,false)
        XCTAssertFalse(ActionCatalog.actions(for:[unsupported],installedOnly:true).contains(where:{$0.id == .mediaConvert}))
    }
    func testUnsafePreviewManifestIsRejectedAndCleaned() async throws {
        let input = try image(in:root), stage = root.appendingPathComponent("preview")
        let jobs = JobCoordinator(transport:UnsafePreviewTransport(url:input),journal:root.appendingPathComponent("jobs"))
        do { _ = try await jobs.preview(.init(inputs:[input],action:.imageConvert,profiles:[ActionCatalog.jpg]),in:stage); XCTFail("Unsafe preview accepted") } catch {}
        XCTAssertFalse(FileManager.default.fileExists(atPath:stage.path)); XCTAssertTrue(FileManager.default.fileExists(atPath:input.path))
    }
}
private struct UnsafePreviewTransport: WorkerTransport {
    var url: URL
    func perform(_ envelope:WorkerEnvelope) async throws -> WorkerResponse { WorkerResponse(manifest:OutputManifest(jobID:envelope.id,outputs:[.init(url:url,sources:envelope.inputs,byteCount:1,format:"jpg")])) }
}

private struct PartialPublicationTransport: WorkerTransport {
    var longName: String
    func perform(_ envelope:WorkerEnvelope) async throws -> WorkerResponse {
        let directory = try XCTUnwrap(envelope.directory), source = try XCTUnwrap(envelope.inputs.first)
        let imageSource = try XCTUnwrap(CGImageSourceCreateWithURL(source as CFURL,nil)), image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(imageSource,0,nil))
        let first = directory.appendingPathComponent("first.png"), second = directory.appendingPathComponent(longName)
        try PDFEngine.saveImage(image,to:first,format:.png,quality:1); let temporary = directory.appendingPathComponent("second-temp.jpg"); try PDFEngine.saveImage(image,to:temporary,format:.jpeg,quality:0.9); try FileManager.default.moveItem(at:temporary,to:second)
        return WorkerResponse(manifest:OutputManifest(jobID:envelope.id,outputs:[.init(url:first,sources:envelope.inputs,byteCount:Int64(try first.resourceValues(forKeys:[.fileSizeKey]).fileSize ?? 0),format:"png"),.init(url:second,sources:envelope.inputs,byteCount:Int64(try second.resourceValues(forKeys:[.fileSizeKey]).fileSize ?? 0),format:"jpg")]))
    }
}
