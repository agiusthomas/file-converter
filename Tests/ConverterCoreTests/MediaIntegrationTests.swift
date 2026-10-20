import XCTest
import Foundation
import AVFoundation
import CoreVideo
import CoreText
import PDFKit
@testable import ConverterCore

final class MediaIntegrationTests: XCTestCase {
    var root: URL!
    override func setUpWithError() throws {
        guard ProcessInfo.processInfo.environment["FILE_CONVERTER_MEDIA_TESTS"] == "1" else { throw XCTSkip("Set FILE_CONVERTER_MEDIA_TESTS=1 with normal access to macOS encoder services.") }
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString); try FileManager.default.createDirectory(at:root,withIntermediateDirectories:false)
    }
    override func tearDownWithError() throws { if let root { try? FileManager.default.removeItem(at:root) } }
    func wave() throws -> URL {
        var pcm = Data(); for i in 0..<32000 { var value = Int16(6000 * sin(Double(i)*2*Double.pi*440/16000)).littleEndian; withUnsafeBytes(of:&value) { pcm.append(contentsOf:$0) } }
        var data = Data("RIFF".utf8)
        func u32(_ value:UInt32) { var value = value.littleEndian; withUnsafeBytes(of:&value) { data.append(contentsOf:$0) } }
        func u16(_ value:UInt16) { var value = value.littleEndian; withUnsafeBytes(of:&value) { data.append(contentsOf:$0) } }
        u32(UInt32(pcm.count+36)); data.append(Data("WAVEfmt ".utf8)); u32(16); u16(1); u16(1); u32(16000); u32(32000); u16(2); u16(16); data.append(Data("data".utf8)); u32(UInt32(pcm.count)); data.append(pcm)
        let url = root.appendingPathComponent("tone.wav"); try data.write(to:url); return url
    }
    func video() async throws -> URL {
        let url = root.appendingPathComponent("clip.mp4"), writer = try AVAssetWriter(outputURL:root.appendingPathComponent("clip.mp4"),fileType:.mp4)
        let input = AVAssetWriterInput(mediaType:.video,outputSettings:[AVVideoCodecKey:AVVideoCodecType.h264,AVVideoWidthKey:64,AVVideoHeightKey:48])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput:input,sourcePixelBufferAttributes:[kCVPixelBufferPixelFormatTypeKey as String:kCVPixelFormatType_32ARGB,kCVPixelBufferWidthKey as String:64,kCVPixelBufferHeightKey as String:48])
        writer.add(input); guard writer.startWriting() else { throw XCTUnwrapError() }; writer.startSession(atSourceTime:.zero)
        for i in 0..<60 {
            while !input.isReadyForMoreMediaData { try await Task.sleep(nanoseconds:1_000_000) }
            var buffer: CVPixelBuffer?; CVPixelBufferCreate(nil,64,48,kCVPixelFormatType_32ARGB,nil,&buffer)
            let image = try XCTUnwrap(buffer); CVPixelBufferLockBaseAddress(image,[])
            memset(CVPixelBufferGetBaseAddress(image),Int32(i*3),CVPixelBufferGetDataSize(image)); CVPixelBufferUnlockBaseAddress(image,[])
            XCTAssertTrue(adaptor.append(image,withPresentationTime:CMTime(value:Int64(i),timescale:30)))
        }
        input.markAsFinished(); await writer.finishWriting(); XCTAssertEqual(writer.status,.completed); return url
    }
    func testNativeAudioConversionAndTrim() async throws {
        let source = try wave(), coordinator = JobCoordinator(transport:InProcessWorkerTransport(),journal:root.appendingPathComponent("jobs"))
        let original = try FileDigest.sha256(source)
        let result = try await coordinator.run(.init(inputs:[source],action:.mediaConvert,profiles:[ActionCatalog.m4a]))
        XCTAssertEqual(result.outputs.first?.duration ?? 0,2,accuracy:0.1)
        var options = OperationOptions(); options.startTime = 0.5; options.endTime = 1.5; options.sampleRate = 48000; options.channels = 2
        let wav = try await coordinator.run(.init(inputs:[source],action:.mediaConvert,profiles:[ActionCatalog.wav],options:options))
        XCTAssertEqual(wav.outputs.first?.duration ?? 0,1,accuracy:0.1); XCTAssertEqual(try FileDigest.sha256(source),original)
    }
    func testNativeAudioSettingsAndPreciseVideoGeometry() async throws {
        let coordinator = JobCoordinator(transport:InProcessWorkerTransport(),journal:root.appendingPathComponent("jobs"))
        var options = OperationOptions(); options.channels = 1; options.sampleRate = 48000; options.bitrate = 96000
        let audio = try await coordinator.run(.init(inputs:[try wave()],action:.mediaConvert,profiles:[ActionCatalog.m4a],options:options))
        let asset = AVURLAsset(url:audio.outputs[0].url)
        let tracks = try await asset.loadTracks(withMediaType:.audio); let track = try XCTUnwrap(tracks.first)
        let formats = try await track.load(.formatDescriptions); let format = try XCTUnwrap(formats.first)
        let stream = try XCTUnwrap(CMAudioFormatDescriptionGetStreamBasicDescription(format))
        XCTAssertEqual(stream.pointee.mChannelsPerFrame,1); XCTAssertEqual(stream.pointee.mSampleRate,48000)
        let source = try await video(); options = .init(); options.maximumDimension = 30; options.rotation = 90
        let output = try await coordinator.run(.init(inputs:[source],action:.mediaConvert,profiles:[ActionCatalog.mp4],options:options))
        XCTAssertEqual(output.outputs[0].width,22); XCTAssertEqual(output.outputs[0].height,30); XCTAssertEqual(output.outputs[0].duration ?? 0,2,accuracy:0.15)
    }
    func testNativeVideoSpeedFrameAndJoin() async throws {
        let source = try await video(), coordinator = JobCoordinator(transport:InProcessWorkerTransport(),journal:root.appendingPathComponent("jobs"))
        var options = OperationOptions(); options.speed = 2
        let faster = try await coordinator.run(.init(inputs:[source],action:.mediaConvert,profiles:[ActionCatalog.mp4],options:options))
        XCTAssertEqual(faster.outputs[0].duration ?? 0,1,accuracy:0.15)
        options = .init(); options.startTime = 0.5
        let frame = try await coordinator.run(.init(inputs:[source],action:.mediaFrame,profiles:[ActionCatalog.png],options:options))
        XCTAssertEqual(frame.outputs[0].width,64); XCTAssertEqual(frame.outputs[0].height,48)
        let joined = try await coordinator.run(.init(inputs:[source,source],action:.mediaJoin,profiles:[ActionCatalog.mp4]))
        XCTAssertEqual(joined.outputs[0].duration ?? 0,4,accuracy:0.15)
    }
    func testLocalOCRAndSearchablePDF() async throws {
        let context = try XCTUnwrap(CGContext(data:nil,width:1200,height:400,bitsPerComponent:8,bytesPerRow:0,space:CGColorSpace(name:CGColorSpace.sRGB)!,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(gray:1,alpha:1)); context.fill(CGRect(x:0,y:0,width:1200,height:400)); context.setFillColor(CGColor(gray:0,alpha:1)); context.textPosition = CGPoint(x:80,y:180)
        let line = CTLineCreateWithAttributedString(NSAttributedString(string:"LOCAL FILE CONVERTER",attributes:[NSAttributedString.Key(kCTFontAttributeName as String):CTFontCreateWithName("Helvetica" as CFString,72,nil)]))
        CTLineDraw(line,context)
        let source = root.appendingPathComponent("scan.png"); try PDFEngine.saveImage(XCTUnwrap(context.makeImage()),to:source,format:.png,quality:1)
        let coordinator = JobCoordinator(transport:InProcessWorkerTransport(),journal:root.appendingPathComponent("jobs"))
        var options = OperationOptions(); options.scanCleanup = true
        let text = try await coordinator.run(.init(inputs:[source],action:.pdfOCR,profiles:[ActionCatalog.txt],options:options))
        XCTAssertTrue(try String(contentsOf:text.outputs[0].url,encoding:.utf8).contains("LOCAL"))
        let pdf = try await coordinator.run(.init(inputs:[source],action:.pdfOCR,profiles:[.init("searchable-pdf","Searchable PDF","pdf")],options:options))
        let document = try XCTUnwrap(PDFDocument(url:pdf.outputs[0].url)); XCTAssertTrue((document.string ?? "").contains("LOCAL")); XCTAssertEqual(document.pageCount,1)
    }
}
private struct XCTUnwrapError: Error {}
