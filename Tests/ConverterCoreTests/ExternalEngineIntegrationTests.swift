import XCTest
import Foundation
import PDFKit
@testable import ConverterCore

/// Development-only adapter tests. These do not bypass production WorkerExecutor's
/// signature checks or cause local tools to appear as installed engine packs.
final class ExternalEngineIntegrationTests: XCTestCase {
    var root: URL!
    override func setUpWithError() throws {
        guard ProcessInfo.processInfo.environment["FILE_CONVERTER_EXTERNAL_TESTS"] == "1" else { throw XCTSkip("Optional development engine tests are disabled.") }
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString); try FileManager.default.createDirectory(at:root,withIntermediateDirectories:false)
    }
    override func tearDownWithError() throws { if let root { try? FileManager.default.removeItem(at:root) } }
    func pack(_ id:String, tools:[String:String]) throws -> InstalledEnginePack {
        for path in tools.values { guard FileManager.default.isExecutableFile(atPath:path) else { throw XCTSkip("Development tool is not installed: \(path)") } }
        let json: [String:Any] = ["schemaVersion":1,"id":id,"version":"1.0.0","minimumAppVersion":"0.2.0","minimumOSVersion":"13.0","architectures":["arm64"],"tools":tools.mapValues { String($0.dropFirst()) },"files":[:],"licenses":["test-only"],"installedBytes":1,"engineVersions":[:]]
        return InstalledEnginePack(location:URL(fileURLWithPath:"/"),manifest:try JSONDecoder().decode(EnginePackManifest.self,from:JSONSerialization.data(withJSONObject:json)))
    }
    func testLibreOfficeRTFToPDFWithIsolatedProfile() async throws {
        let engine = NativeEngine(packs:[try pack("documents",tools:["soffice":"/Applications/LibreOffice.app/Contents/MacOS/soffice"])])
        let input = root.appendingPathComponent("document.rtf")
        try Data(#"{\rtf1\ansi\deff0 {\fonttbl {\f0 Helvetica;}}\f0\fs28 Local document conversion fixture.\par}"#.utf8).write(to:input)
        let result = try await engine.execute(.init(inputs:[input],action:.documentConvert,profiles:[ActionCatalog.pdf]),in:root.appendingPathComponent("output"))
        let pdf = try XCTUnwrap(PDFDocument(url:result.outputs[0].url)); XCTAssertTrue((pdf.string ?? "").contains("Local document conversion fixture")); XCTAssertEqual(pdf.pageCount,1)
    }
    func testSpreadsheetExportsEverySelectedSheetAndPreservesZeros() async throws {
        let engine = NativeEngine(packs:[try pack("documents",tools:["soffice":"/Applications/LibreOffice.app/Contents/MacOS/soffice"])])
        let contents = root.appendingPathComponent("book-files"); try FileManager.default.createDirectory(at:contents.appendingPathComponent("META-INF"),withIntermediateDirectories:true)
        let mimetype = contents.appendingPathComponent("mimetype"), content = contents.appendingPathComponent("content.xml"), manifest = contents.appendingPathComponent("META-INF/manifest.xml")
        try Data("application/vnd.oasis.opendocument.spreadsheet".utf8).write(to:mimetype)
        try Data(#"<?xml version="1.0" encoding="UTF-8"?><office:document-content xmlns:office="urn:oasis:names:tc:opendocument:xmlns:office:1.0" xmlns:table="urn:oasis:names:tc:opendocument:xmlns:table:1.0" xmlns:text="urn:oasis:names:tc:opendocument:xmlns:text:1.0" office:version="1.2"><office:body><office:spreadsheet><table:table table:name="First"><table:table-row><table:table-cell office:value-type="string"><text:p>001</text:p></table:table-cell><table:table-cell office:value-type="string"><text:p>First sheet</text:p></table:table-cell></table:table-row></table:table><table:table table:name="Second"><table:table-row><table:table-cell office:value-type="string"><text:p>002</text:p></table:table-cell><table:table-cell office:value-type="string"><text:p>Second sheet</text:p></table:table-cell></table:table-row></table:table></office:spreadsheet></office:body></office:document-content>"#.utf8).write(to:content)
        try Data(#"<?xml version="1.0"?><manifest:manifest xmlns:manifest="urn:oasis:names:tc:opendocument:xmlns:manifest:1.0" manifest:version="1.2"><manifest:file-entry manifest:full-path="/" manifest:media-type="application/vnd.oasis.opendocument.spreadsheet"/><manifest:file-entry manifest:full-path="content.xml" manifest:media-type="text/xml"/></manifest:manifest>"#.utf8).write(to:manifest)
        let input = root.appendingPathComponent("book.ods"); try ArchiveEngine.create([mimetype,content,contents.appendingPathComponent("META-INF")],to:input,format:"zip")
        let profile = OutputProfile("csv","CSV · selected sheets","csv")
        let all = try await engine.execute(.init(inputs:[input],action:.documentConvert,profiles:[profile]),in:root.appendingPathComponent("all"))
        let sheets = try FileManager.default.contentsOfDirectory(at:all.outputs[0].url,includingPropertiesForKeys:nil)
        XCTAssertEqual(sheets.count,2)
        let rows = try sheets.map { try TextEngine.table(TextEngine.read($0),delimiter:",") }
        XCTAssertEqual(Set(rows.compactMap { $0.first?.first }),["001","002"])
        var options = OperationOptions(); options.sheet = "2"
        let selected = try await engine.execute(.init(inputs:[input],action:.documentConvert,profiles:[profile],options:options),in:root.appendingPathComponent("selected"))
        let files = try FileManager.default.contentsOfDirectory(at:selected.outputs[0].url,includingPropertiesForKeys:nil); XCTAssertEqual(files.count,1)
        XCTAssertTrue(try TextEngine.read(files[0]).contains("Second sheet"))
    }
    func testFFmpegAudioAndWebMAdapters() async throws {
        let pack = try pack("media",tools:["ffmpeg":"/opt/homebrew/bin/ffmpeg","ffprobe":"/opt/homebrew/bin/ffprobe"])
        let ffmpeg = URL(fileURLWithPath:"/opt/homebrew/bin/ffmpeg")
        let input = root.appendingPathComponent("source.mp4")
        _ = try await CommandRunner.run(ffmpeg,arguments:["-nostdin","-v","error","-f","lavfi","-i","testsrc=size=96x64:rate=10:duration=1","-f","lavfi","-i","sine=frequency=440:sample_rate=44100:duration=1","-c:v","libx264","-pix_fmt","yuv420p","-c:a","aac","-shortest",input.path],in:root)
        let engine = NativeEngine(packs:[pack]); let mp3 = OutputProfile("mp3","MP3","mp3",audioCodec:"libmp3lame")
        let audio = try await engine.execute(.init(inputs:[input],action:.mediaConvert,profiles:[mp3]),in:root.appendingPathComponent("audio"))
        XCTAssertTrue(audio.outputs[0].byteCount > 0); XCTAssertGreaterThan(audio.outputs[0].duration ?? 0,0.9)
        let profile = OutputProfile("webm","WebM · VP9 / Opus","webm",videoCodec:"libvpx-vp9",audioCodec:"libopus")
        var options = OperationOptions(); options.sampleRate = 48000; options.maximumDimension = 80
        let video = try await engine.execute(.init(inputs:[input],action:.mediaConvert,profiles:[profile],options:options),in:root.appendingPathComponent("video"))
        XCTAssertLessThanOrEqual(video.outputs[0].width ?? 1000,80); XCTAssertGreaterThan(video.outputs[0].duration ?? 0,0.9)
        var copyOptions = OperationOptions(); copyOptions.streamCopy = true
        do { _ = try await engine.execute(.init(inputs:[input],action:.mediaConvert,profiles:[mp3],options:copyOptions),in:root.appendingPathComponent("incompatible-copy")); XCTFail("AAC was claimed to be stream-copy compatible with MP3") } catch { XCTAssertTrue(error.localizedDescription.contains("Turn off stream copy")) }
        let frame = root.appendingPathComponent("frame.png"); try await ExternalEngine(packs:[pack]).frame(input,time:0.5,to:frame,in:root)
        let frameAsset = try await AssetInspector.inspect(frame); XCTAssertEqual(frameAsset.width,96); XCTAssertEqual(frameAsset.height,64)
    }
}
