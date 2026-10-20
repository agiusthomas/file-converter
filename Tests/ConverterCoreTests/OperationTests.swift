import XCTest
import Foundation
import ImageIO
import PDFKit
import CoreGraphics
@testable import ConverterCore

final class OperationTests: XCTestCase {
    var root: URL!
    override func setUpWithError() throws { root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString); try FileManager.default.createDirectory(at:root,withIntermediateDirectories:false) }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at:root) }
    func image(_ name:String = "picture.png") throws -> URL {
        let url = root.appendingPathComponent(name)
        let context = try XCTUnwrap(CGContext(data:nil,width:40,height:20,bitsPerComponent:8,bytesPerRow:0,space:CGColorSpace(name:CGColorSpace.sRGB)!,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red:1,green:0,blue:0,alpha:1)); context.fill(CGRect(x:0,y:0,width:40,height:20))
        try PDFEngine.saveImage(XCTUnwrap(context.makeImage()),to:url,format:.png,quality:1)
        return url
    }
    func pdf(_ name:String = "pages.pdf", widths:[Double] = [100,200,300]) throws -> URL {
        let url = root.appendingPathComponent(name)
        let consumer = try XCTUnwrap(CGDataConsumer(url:url as CFURL)), context = try XCTUnwrap(CGContext(consumer:consumer,mediaBox:nil,nil))
        for width in widths { var box = CGRect(x:0,y:0,width:width,height:100); context.beginPDFPage([kCGPDFContextMediaBox:Data(bytes:&box,count:MemoryLayout<CGRect>.size)] as CFDictionary); context.setFillColor(CGColor(gray:0.5,alpha:1)); context.fill(box); context.endPDFPage() }
        context.closePDF(); return url
    }
    func coordinator(_ transport:any WorkerTransport = InProcessWorkerTransport()) -> JobCoordinator { JobCoordinator(transport:transport,journal:root.appendingPathComponent("jobs")) }
    func testInspectionUsesContentInsteadOfExtension() async throws {
        let input = try image("misleading.txt")
        let descriptor = try await AssetInspector.inspect(input)
        XCTAssertEqual(descriptor.family,.image); XCTAssertEqual(descriptor.width,40)
        let fake = root.appendingPathComponent("fake.png"); try Data("This is text, not image data.".utf8).write(to:fake)
        let text = try await AssetInspector.inspect(fake)
        XCTAssertEqual(text.family,.text)
        XCTAssertFalse(ActionCatalog.actions(for:[text]).contains(where:{$0.id == .imageConvert}))
    }
    func testImageRotationResizeMultipleOutputsAndOriginalIntegrity() async throws {
        let input = try image(); let before = try FileDigest.sha256(input)
        var options = OperationOptions(); options.rotation = 90; options.maximumDimension = 10
        let manifest = try await coordinator().run(.init(inputs:[input],action:.imageConvert,profiles:[ActionCatalog.png,ActionCatalog.jpg],options:options))
        XCTAssertEqual(manifest.outputs.count,2)
        for output in manifest.outputs { XCTAssertEqual(output.width,5); XCTAssertEqual(output.height,10); XCTAssertTrue(output.validated); XCTAssertNotNil(output.sha256) }
        XCTAssertEqual(try FileDigest.sha256(input),before)
        XCTAssertNotEqual(manifest.outputs[0].url,input)
    }
    func testJPGWheelChoicesProduceValidatedWebPAVIFAndPDF() async throws {
        let jobs = coordinator()
        let png = try image()
        let jpeg = try await jobs.run(.init(inputs:[png],action:.imageConvert,profiles:[ActionCatalog.jpg]))
        let source = try XCTUnwrap(jpeg.outputs.first?.url)
        let originalHash = try FileDigest.sha256(source)
        let assets = try await AssetInspector.inspect(source)
        let choices = WheelChoice.common([assets]).filter { ["avif","webp","pdf"].contains($0.profile.id) }
        XCTAssertTrue(choices.contains { $0.profile.id == "webp" })
        XCTAssertTrue(choices.contains { $0.profile.id == "pdf" })
        for choice in choices {
            let result = try await jobs.run(.init(inputs:[source],action:choice.action,profiles:[choice.profile]))
            let output = try XCTUnwrap(result.outputs.first)
            XCTAssertTrue(output.validated)
            let inspected = try await AssetInspector.inspect(output.url)
            XCTAssertEqual(inspected.format, choice.profile.id)
        }
        XCTAssertEqual(try FileDigest.sha256(source), originalHash)
    }
    func testUnreachableImageSizePublishesNothing() async throws {
        let input = try image(); var options = OperationOptions(); options.targetBytes = 1
        do { _ = try await coordinator().run(.init(inputs:[input],action:.imageConvert,profiles:[ActionCatalog.jpg],options:options)); XCTFail("Unreachable target succeeded") } catch {}
        XCTAssertFalse(FileManager.default.fileExists(atPath:root.appendingPathComponent("picture.jpg").path))
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath:root.path).contains(where:{$0.hasPrefix(".file-converter-")}))
    }
    func testPDFReorderAndRotation() async throws {
        let input = try pdf(); var options = OperationOptions(); options.pages = [3,1,2]; options.rotation = 90
        let manifest = try await coordinator().run(.init(inputs:[input],action:.pdfOrganize,profiles:[ActionCatalog.pdf],options:options))
        let document = try XCTUnwrap(PDFDocument(url:manifest.outputs[0].url))
        XCTAssertEqual(document.pageCount,3); XCTAssertEqual(document.page(at:0)?.bounds(for:.mediaBox).width,300); XCTAssertEqual(document.page(at:1)?.bounds(for:.mediaBox).width,100); XCTAssertEqual(document.page(at:2)?.rotation,90)
        XCTAssertEqual(PDFDocument(url:input)?.page(at:0)?.rotation,0)
    }
    func testPDFMergeSplitAndPageImages() async throws {
        let first = try pdf("first.pdf",widths:[100]), second = try pdf("second.pdf",widths:[200,300]); let jobs = coordinator()
        let merged = try await jobs.run(.init(inputs:[first,second],action:.pdfMerge,profiles:[ActionCatalog.pdf]))
        XCTAssertEqual(PDFDocument(url:merged.outputs[0].url)?.pageCount,3)
        let split = try await jobs.run(.init(inputs:[merged.outputs[0].url],action:.pdfSplit,profiles:[ActionCatalog.pdf]))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath:split.outputs[0].url.path).count,3)
        var options = OperationOptions(); options.pages = [2]; options.dpi = 72
        let exported = try await jobs.run(.init(inputs:[merged.outputs[0].url],action:.pdfExport,profiles:[ActionCatalog.png],options:options))
        let image = exported.outputs[0].url.appendingPathComponent("Page 0001.png")
        let inspected = try await AssetInspector.inspect(image); XCTAssertEqual(inspected.width,200); XCTAssertEqual(inspected.height,100)
    }
    func testInvalidPDFPagePublishesNothing() async throws {
        let input = try pdf(); var options = OperationOptions(); options.pages = [99]
        do { _ = try await coordinator().run(.init(inputs:[input],action:.pdfSplit,profiles:[ActionCatalog.pdf],options:options)); XCTFail("Invalid page succeeded") } catch {}
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath:root.path).filter { !$0.hasPrefix("jobs") },["pages.pdf"])
    }
    func testPDFPasswordAndJournalRedaction() async throws {
        let input = try pdf(); var options = OperationOptions(); options.outputPassword = "test-only-secret"
        let jobs = coordinator(); let request = OperationRequest(inputs:[input],action:.pdfProtect,profiles:[ActionCatalog.pdf],options:options)
        let manifest = try await jobs.run(request)
        let protected = try XCTUnwrap(PDFDocument(url:manifest.outputs[0].url)); XCTAssertTrue(protected.isLocked); XCTAssertTrue(protected.unlock(withPassword:"test-only-secret")); XCTAssertEqual(protected.pageCount,3)
        let journal = try String(contentsOf:root.appendingPathComponent("jobs/\(request.id.uuidString).json"),encoding:.utf8)
        XCTAssertFalse(journal.contains("test-only-secret"))
    }
    func testImagesAggregateIntoOnePDF() async throws {
        let first = try image("first.png"), second = try image("second.png")
        var options = OperationOptions(); options.pageWidth = 595; options.pageHeight = 842; options.margin = 24
        let result = try await coordinator().run(.init(inputs:[first,second],action:.imagesToPDF,profiles:[ActionCatalog.pdf],options:options))
        let output = try XCTUnwrap(PDFDocument(url:result.outputs[0].url)); XCTAssertEqual(output.pageCount,2); XCTAssertEqual(output.page(at:0)?.bounds(for:.mediaBox).width,595)
    }
    func testArchiveRoundTripFormatsAndSelection() async throws {
        guard ArchiveEngine.available else { throw XCTSkip("System libarchive unavailable") }
        let first = root.appendingPathComponent("first.txt"), second = root.appendingPathComponent("second.txt")
        try Data("first data".utf8).write(to:first); try Data("second data".utf8).write(to:second)
        for format in ["zip","tar","tar.gz","7z"] {
            let output = root.appendingPathComponent("test.\(format)"); try ArchiveEngine.create([first,second],to:output,format:format)
            XCTAssertEqual(Set(try ArchiveEngine.list(output).map(\.name)),Set(["first.txt","second.txt"]))
            let destination = root.appendingPathComponent("extracted-\(format)")
            let results = try ArchiveEngine.extract(output,to:destination,selected:["second.txt"])
            XCTAssertEqual(results.count,1); XCTAssertEqual(try Data(contentsOf:results[0]),Data("second data".utf8)); XCTAssertFalse(FileManager.default.fileExists(atPath:destination.appendingPathComponent("first.txt").path))
        }
    }
    func testArchiveUnsafePathsAndLinksRejected() throws {
        for path in ["../escape","/absolute","a/../../escape","a\\..\\escape","a/./b","C:/file","bad\nname"] { XCTAssertThrowsError(try ArchiveEngine.safeName(path)) }
        let original = try image(); let link = root.appendingPathComponent("link"); try FileManager.default.createSymbolicLink(at:link,withDestinationURL:original)
        XCTAssertThrowsError(try ArchiveEngine.create([link],to:root.appendingPathComponent("bad.zip"),format:"zip"))
    }
    func testSubtitleTimingAndRoundTrip() throws {
        let input = "1\n00:00:01,200 --> 00:00:02,400\nHello\nworld\n\n2\n00:00:03,000 --> 00:00:04,000\nBye\n"
        let parsed = try TextEngine.cues(input); let vtt = try TextEngine.subtitle(parsed,format:"vtt",offset:0.5)
        XCTAssertTrue(vtt.hasPrefix("WEBVTT")); XCTAssertEqual(try TextEngine.cues(vtt)[0].start,1.7,accuracy:0.001)
        XCTAssertThrowsError(try TextEngine.subtitle(parsed,format:"srt",offset:-2))
        XCTAssertThrowsError(try TextEngine.cues("1\n00:00:05,000 --> 00:00:02,000\nBad\n"))
    }
    func testTablePreservesLeadingZerosQuotesAndNewlines() throws {
        let input = "id,name,notes\n001,\"A, B\",\"two\nlines\"\n002,\"quoted \"\"name\"\"\",end\n"
        let rows = try TextEngine.table(input,delimiter:",")
        XCTAssertEqual(rows[1][0],"001"); XCTAssertEqual(rows[1][2],"two\nlines")
        let tsv = TextEngine.delimited(rows,delimiter:"\t"); XCTAssertEqual(try TextEngine.table(tsv,delimiter:"\t"),rows)
        XCTAssertThrowsError(try TextEngine.table("a,\"unterminated",delimiter:","))
    }
    func testEncodingCannotSilentlyDropCharacters() throws {
        var options = OperationOptions(); options.encoding = "ascii"
        XCTAssertThrowsError(try TextEngine.write("日本語",to:root.appendingPathComponent("out.txt"),options:options))
    }
    func testMissingPacksStayDiscoverableButCannotExecute() async throws {
        let text = AssetDescriptor(source:root.appendingPathComponent("note.txt"),family:.text,format:"txt",byteCount:10)
        XCTAssertEqual(ActionCatalog.actions(for:[text]).first(where:{$0.id == .documentConvert})?.available,false)
        XCTAssertFalse(ActionCatalog.actions(for:[text],installedOnly:true).contains(where:{$0.id == .documentConvert}))
    }
    func testCoordinatorRejectsWorkerOutputOutsideStaging() async throws {
        let input = try image(); let jobs = coordinator(UnsafeTransport(output:input))
        do { _ = try await jobs.run(.init(inputs:[input],action:.imageConvert,profiles:[ActionCatalog.jpg])); XCTFail("Unsafe output accepted") } catch {}
        XCTAssertTrue(FileManager.default.fileExists(atPath:input.path))
    }
    func testConcurrentJobsNeverOverwrite() async throws {
        let input = try image(); let jobs = coordinator()
        async let first = jobs.run(OperationRequest(inputs:[input],action:.imageConvert,profiles:[ActionCatalog.jpg]))
        async let second = jobs.run(OperationRequest(inputs:[input],action:.imageConvert,profiles:[ActionCatalog.jpg]))
        let results = try await [first,second]; XCTAssertNotEqual(results[0].outputs[0].url,results[1].outputs[0].url)
        let records = try await jobs.records(); XCTAssertEqual(records.count,2)
    }
    func testCancelledJobCleansStagingAndPersistsFailure() async throws {
        let input = try image(); let jobs = coordinator(SlowTransport())
        let task = Task { try await jobs.run(.init(inputs:[input],action:.imageConvert,profiles:[ActionCatalog.jpg])) }
        try await Task.sleep(nanoseconds:100_000_000); task.cancel()
        do { _ = try await task.value; XCTFail("Cancelled job succeeded") } catch {}
        let records = try await jobs.records(); XCTAssertEqual(records.last?.state,.cancelled)
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath:root.path).contains(where:{$0.hasPrefix(".file-converter-")}))
    }
    func testRecipeValidationAndExecution() async throws {
        let input = try image(); let jobs = coordinator()
        let recipe = Recipe(name:"Two outputs",steps:[.init(action:.imageConvert,profiles:[ActionCatalog.png,ActionCatalog.jpg],export:true)])
        let result = try await jobs.run(recipe,inputs:[input]); XCTAssertEqual(result.outputs.count,2)
        XCTAssertThrowsError(try Recipe(name:"",steps:[]).validate())
    }
    func testEnginePackTamperingAndUnsignedPackRejected() throws {
        let path = root.appendingPathComponent("fake.bundle"); try FileManager.default.createDirectory(at:path,withIntermediateDirectories:false)
        XCTAssertThrowsError(try EnginePacks.verify(path,trustedTeam:"NOTATRUSTEDTEAM"))
    }
    func testNonfiniteAndInvalidOptionsRejected() throws {
        var options = OperationOptions(); options.dpi = .infinity; XCTAssertThrowsError(try options.validated())
        options = .init(); options.pages = [0]; XCTAssertThrowsError(try options.validated())
        options = .init(); options.outputName = "../escape"; XCTAssertThrowsError(try options.validated())
    }
    func testBundledWebPEncodingPreservesDimensionsAndAlpha() async throws {
        let input = try image(); let source = try Data(contentsOf:input)
        let manifest = try await coordinator().run(.init(inputs:[input],action:.imageConvert,profiles:[.init("webp","WEBP","webp")]))
        let asset = try await AssetInspector.inspect(manifest.outputs[0].url)
        XCTAssertEqual(asset.format,"webp"); XCTAssertEqual(asset.width,40); XCTAssertEqual(asset.height,20); XCTAssertEqual(try Data(contentsOf:input),source)
        XCTAssertTrue(manifest.notices.contains(where:{$0.contains("omit source metadata")}))
    }
    func testStableWatcherSkipsBaselineAndWaitsForWritesToSettle() {
        let existing = root.appendingPathComponent("existing.png"), new = root.appendingPathComponent("new.png")
        let time = Date(timeIntervalSince1970:100), old = FileObservation(size:10,modified:Date(timeIntervalSince1970:1))
        var tracker = StableFileTracker(); tracker.baseline([existing:old])
        XCTAssertTrue(tracker.ready([existing:old],now:time).isEmpty)
        var files = [existing:old,new:FileObservation(size:20,modified:time)]
        XCTAssertTrue(tracker.ready(files,now:time).isEmpty)
        files[new] = FileObservation(size:40,modified:time.addingTimeInterval(1))
        XCTAssertTrue(tracker.ready(files,now:time.addingTimeInterval(2)).isEmpty)
        XCTAssertEqual(tracker.ready(files,now:time.addingTimeInterval(6)),[new])
        XCTAssertTrue(tracker.ready(files,now:time.addingTimeInterval(12)).isEmpty)
    }
    func testPartialOptionsDecodeWithSafeDefaults() throws {
        let options = try JSONDecoder().decode(OperationOptions.self,from:Data(#"{"maximumDimension":1000,"preserveMetadata":false}"#.utf8))
        XCTAssertEqual(options.maximumDimension,1000); XCTAssertFalse(options.preserveMetadata); XCTAssertEqual(options.dpi,144); _ = try options.validated()
    }
    func testInterruptedRecoveryPreservesOutputsAndRemovesOnlyItsStage() async throws {
        let input = try image(); let jobs = coordinator(); let request = OperationRequest(inputs:[input],action:.imageConvert,profiles:[ActionCatalog.jpg])
        var record = JobRecord(request:request,state:.running); record.ownerPID = Int32.max
        let stage = root.appendingPathComponent(".file-converter-\(request.id.uuidString)"); try FileManager.default.createDirectory(at:stage,withIntermediateDirectories:false); record.stageDirectory = stage
        let journal = root.appendingPathComponent("jobs"); try FileManager.default.createDirectory(at:journal,withIntermediateDirectories:false)
        try JSONEncoder().encode(record).write(to:journal.appendingPathComponent(request.id.uuidString + ".json"))
        let recovered = try await jobs.records(recoverInterrupted:true)
        XCTAssertEqual(recovered.first?.state,.interrupted); XCTAssertFalse(FileManager.default.fileExists(atPath:stage.path)); XCTAssertTrue(FileManager.default.fileExists(atPath:input.path))
    }
    func testPreviewDoesNotPublishOrCreateAnActivityRecord() async throws {
        let input = try image(), jobs = coordinator(), stage = root.appendingPathComponent("preview")
        let output = try await jobs.preview(.init(inputs:[input],action:.imageConvert,profiles:[ActionCatalog.jpg]),in:stage)
        XCTAssertTrue(output.outputs[0].url.path.hasPrefix(stage.path)); XCTAssertFalse(FileManager.default.fileExists(atPath:root.appendingPathComponent("picture.jpg").path))
        let records = try await jobs.records(); XCTAssertTrue(records.isEmpty)
    }
}
private struct UnsafeTransport: WorkerTransport {
    var output: URL
    func perform(_ envelope:WorkerEnvelope) async throws -> WorkerResponse { WorkerResponse(manifest:OutputManifest(jobID:envelope.id,outputs:[OutputArtifact(url:output,sources:envelope.inputs,byteCount:1,format:"jpg")])) }
}
private struct SlowTransport: WorkerTransport {
    func perform(_ envelope:WorkerEnvelope) async throws -> WorkerResponse { try await Task.sleep(nanoseconds:30_000_000_000); return WorkerResponse(error:"Unexpected completion") }
}
