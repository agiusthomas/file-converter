import XCTest
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import ConverterCore

final class ImageConversionTests: XCTestCase {
    private var directory: URL!
    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("file-converter-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: directory) }

    private func fixture(name: String = "source.png", type: String = UTType.png.identifier, pages: Int = 1, orientation: Int = 1) throws -> URL {
        let url = directory.appendingPathComponent(name)
        let context = try XCTUnwrap(CGContext(data: nil, width: 12, height: 8, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.clear(CGRect(x: 0, y: 0, width: 12, height: 8))
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 6, y: 0, width: 6, height: 8))
        let image = try XCTUnwrap(context.makeImage())
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, type as CFString, pages, nil))
        for _ in 0..<pages { CGImageDestinationAddImage(destination, image, [kCGImagePropertyOrientation: orientation, kCGImagePropertyExifDictionary: [kCGImagePropertyExifUserComment: "private fixture metadata"]] as CFDictionary) }
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return url
    }
    private func decoded(_ url: URL) throws -> CGImage {
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
        return try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
    }
    private func rgba(_ image: CGImage) throws -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        try bytes.withUnsafeMutableBytes { buffer in
            let context = try XCTUnwrap(CGContext(data: buffer.baseAddress, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        return bytes
    }
    func testJPEGFlattensTransparencyAndNeverOverwritesExistingResult() async throws {
        let source = try fixture()
        let original = try Data(contentsOf: source)
        let existing = directory.appendingPathComponent("source.jpg")
        let sentinel = Data("existing file must survive".utf8)
        try sentinel.write(to: existing)
        let result = try await ImageConverter().convert(.init(source: source, format: .jpeg, options: .init(quality: 1)))
        XCTAssertEqual(result.output.lastPathComponent, "source 2.jpg")
        XCTAssertEqual(try Data(contentsOf: existing), sentinel)
        XCTAssertEqual(try Data(contentsOf: source), original)
        let image = try decoded(result.output)
        XCTAssertEqual(image.width, 12); XCTAssertEqual(image.height, 8)
        let pixels = try rgba(image)
        XCTAssertGreaterThan(pixels[0], 240); XCTAssertGreaterThan(pixels[1], 240); XCTAssertGreaterThan(pixels[2], 240)
        XCTAssertEqual(pixels[3], 255)
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: directory.path).contains { $0.hasPrefix(".file-converter-") })
    }
    func testOrientationIsAppliedOnceAndPNGPreservesAlpha() async throws {
        let oriented = try fixture(name: "rotated.tiff", type: UTType.tiff.identifier, orientation: 6)
        let converter = ImageConverter()
        let result = try await converter.convert(.init(source: oriented, format: .png))
        let image = try decoded(result.output)
        XCTAssertEqual(image.width, 8); XCTAssertEqual(image.height, 12)
        let bytes = try rgba(image)
        XCTAssertTrue(stride(from: 3, to: bytes.count, by: 4).contains { bytes[$0] == 0 })
        let encoded = try XCTUnwrap(CGImageSourceCreateWithURL(result.output as CFURL, nil))
        let properties = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(encoded, 0, nil) as? [CFString: Any])
        XCTAssertEqual((properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1, 1)
    }
    func testMultipageImageCannotSilentlyBecomeOnePNGButCanBecomePDF() async throws {
        let source = try fixture(name: "pages.tiff", type: UTType.tiff.identifier, pages: 2)
        let converter = ImageConverter()
        do {
            _ = try await converter.convert(.init(source: source, format: .png))
            XCTFail("A multi-page image must not be silently flattened")
        } catch { XCTAssertEqual(error.localizedDescription, ConversionError.multipleFrames.localizedDescription) }
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("pages.png").path))
        let result = try await converter.convert(.init(source: source, format: .pdf))
        let pdf = try XCTUnwrap(CGPDFDocument(result.output as CFURL))
        XCTAssertEqual(pdf.numberOfPages, 2)
    }
    func testMalformedInputPublishesNothing() async throws {
        let source = directory.appendingPathComponent("broken.png")
        try Data("not an image".utf8).write(to: source)
        do { _ = try await ImageConverter().convert(.init(source: source, format: .jpeg)); XCTFail("Malformed image accepted") }
        catch { XCTAssertTrue(error is ConversionError) }
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path), ["broken.png"])
    }
    func testMetadataOptionRemovesTheFixtureComment() async throws {
        let source = try fixture(name: "metadata.tiff", type: UTType.tiff.identifier)
        let converter = ImageConverter()
        let copied = try await converter.convert(.init(source: source, format: .jpeg))
        let stripped = try await converter.convert(.init(source: source, format: .jpeg, options: .init(preserveMetadata: false)))
        func comment(_ url: URL) throws -> String? {
            let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
            return (properties?[kCGImagePropertyExifDictionary] as? [CFString: Any])?[kCGImagePropertyExifUserComment] as? String
        }
        XCTAssertEqual(try comment(copied.output), "private fixture metadata")
        XCTAssertNil(try comment(stripped.output))
    }
    func testTIFFConversionKeepsEveryPage() async throws {
        let source = try fixture(name: "book.tiff", type: UTType.tiff.identifier, pages: 3)
        let before = try Data(contentsOf: source)
        let result = try await ImageConverter().convert(.init(source: source, format: .tiff))
        let output = try XCTUnwrap(CGImageSourceCreateWithURL(result.output as CFURL, nil))
        XCTAssertEqual(CGImageSourceGetCount(output), 3)
        for index in 0..<3 {
            let page = try XCTUnwrap(CGImageSourceCreateImageAtIndex(output, index, nil))
            XCTAssertEqual(page.width, 12); XCTAssertEqual(page.height, 8)
        }
        XCTAssertEqual(try Data(contentsOf: source), before)
    }
    func testConcurrentPublishersAllocateDistinctNamesAtomically() throws {
        let source = directory.appendingPathComponent("photo.png")
        let destination = directory!
        let lock = NSLock()
        var outputs: [URL] = []
        var failures: [String] = []
        DispatchQueue.concurrentPerform(iterations: 16) { index in
            do {
                let stage = destination.appendingPathComponent("stage-\(index)")
                try Data("payload-\(index)".utf8).write(to: stage)
                let output = try AtomicPublisher.publish(stagedFile: stage, source: source, directory: destination, extension: "jpg")
                lock.lock(); outputs.append(output); lock.unlock()
            } catch { lock.lock(); failures.append(error.localizedDescription); lock.unlock() }
        }
        XCTAssertTrue(failures.isEmpty, failures.joined(separator: ", "))
        XCTAssertEqual(Set(outputs).count, 16)
        let payloads = try Set(outputs.map { try String(contentsOf: $0, encoding: .utf8) })
        XCTAssertEqual(payloads.count, 16)
    }
}
