import AppKit
import XCTest
import ConverterCore
@testable import FileConverter

final class WheelBackgroundConversionTests: XCTestCase {
    @MainActor func testWheelConversionsStayInFinderAndPublishBesideOriginals() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let context = try XCTUnwrap(CGContext(data: nil, width: 40, height: 20, bitsPerComponent: 8,
                                             bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 40, height: 20))
        var sources: [URL] = []
        for folder in ["First", "Second"] {
            let directory = root.appendingPathComponent(folder)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let source = directory.appendingPathComponent("image.jpg")
            try PDFEngine.saveImage(XCTUnwrap(context.makeImage()), to: source, format: .jpeg, quality: 1)
            sources.append(source)
        }
        let originalHashes = try sources.map { try FileDigest.sha256($0) }
        let coordinator = JobCoordinator(transport: InProcessWorkerTransport(), journal: root.appendingPathComponent("Jobs"))
        let soundContext = SoundTestContext(); defer { soundContext.cleanUp() }
        let model = AppModel(coordinator: coordinator, sounds: soundContext.makeSounds())
        // Workspace destination settings must not redirect quick Finder actions.
        model.destination = root.appendingPathComponent("Other destination")
        var windowRequests = 0
        model.onShowWindow = { windowRequests += 1 }
        let choices = WheelChoice.common([
            AssetDescriptor(source: sources[0], family: .image, format: "jpg", byteCount: 1)
        ])
        let webp = try XCTUnwrap(choices.first { $0.profile.id == "webp" })
        let pdf = try XCTUnwrap(choices.first { $0.profile.id == "pdf" })
        model.performWheel(sources, choice: webp)
        model.performWheel(sources, choice: pdf)
        XCTAssertEqual(windowRequests, 0)
        for _ in 0..<500 {
            if !model.isProcessing && model.jobs.count == 3 && model.jobs.allSatisfy({ [.succeeded, .failed, .cancelled].contains($0.state) }) { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertEqual(model.jobs.count, 3)
        for job in model.jobs {
            XCTAssertEqual(job.state, .succeeded, job.error ?? "Job did not finish")
            let output = try XCTUnwrap(job.manifest?.outputs.first)
            XCTAssertEqual(output.url.deletingLastPathComponent().standardizedFileURL,
                           job.request.inputs[0].deletingLastPathComponent().standardizedFileURL)
            XCTAssertTrue(output.validated)
        }
        XCTAssertEqual(try sources.map { try FileDigest.sha256($0) }, originalHashes)
        XCTAssertEqual(windowRequests, 0)

        // Normal workspace submissions still request their window.
        model.enqueue(OperationRequest(inputs: [sources[0]], action: .imageConvert, profiles: [webp.profile]))
        XCTAssertEqual(windowRequests, 1)
        for _ in 0..<500 {
            if !model.isProcessing && model.jobs.count == 4 && model.jobs.allSatisfy({ [.succeeded, .failed, .cancelled].contains($0.state) }) { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertEqual(model.jobs.last?.state, .succeeded)
        XCTAssertEqual(windowRequests, 1)
    }
}
