import AppKit
import ConverterCore
import XCTest
@testable import FileConverter

final class ConversionSoundTests: XCTestCase {
    private func image(in root: URL, name: String = "source.png") throws -> URL {
        let source = root.appendingPathComponent(name)
        let context = try XCTUnwrap(CGContext(data: nil, width: 20, height: 10, bitsPerComponent: 8,
            bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 20, height: 10))
        try PDFEngine.saveImage(XCTUnwrap(context.makeImage()), to: source, format: .png, quality: 1)
        return source
    }

    @MainActor private func settle(_ model: AppModel) async throws {
        for _ in 0..<500 {
            if !model.isProcessing && !model.isInspecting && !model.isPreviewing { return }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("Conversion did not settle")
    }

    @MainActor func testOverlappingWheelAndWorkspaceBatchesPlayOnceEachWithoutOpeningWindow() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let context = SoundTestContext(); defer { context.cleanUp() }
        let coordinator = JobCoordinator(transport: InProcessWorkerTransport(), journal: root.appendingPathComponent("Jobs"))
        let model = AppModel(coordinator: coordinator, sounds: context.makeSounds())
        let sources = try [image(in: root), image(in: root, name: "second.png")]
        let choices = WheelChoice.common([AssetDescriptor(source: sources[0], family: .image, format: "png", byteCount: 1)])
        let webp = try XCTUnwrap(choices.first { $0.profile.id == "webp" })
        let pdf = try XCTUnwrap(choices.first { $0.profile.id == "pdf" })
        var windows = 0; model.onShowWindow = { windows += 1 }
        model.performWheel(sources, choice: webp)
        model.performWheel(sources, choice: pdf)
        try await settle(model)
        XCTAssertEqual(windows, 0)
        XCTAssertEqual(model.jobs.filter { $0.state == .succeeded }.count, 3)
        XCTAssertEqual(context.playback.played, [.success, .success])

        model.setSources(sources); try await settle(model)
        model.selectAction(.imageConvert); model.selectedProfileID = "jpg"
        model.convertSelection(); try await settle(model)
        XCTAssertEqual(windows, 1)
        XCTAssertEqual(context.playback.played, [.success, .success, .success])
        XCTAssertEqual(model.jobs.filter { $0.state == .succeeded }.count, 5)
    }

    @MainActor func testPartialFailureSubmissionFailureAndImmediateCancellationStaySilent() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let context = SoundTestContext(); defer { context.cleanUp() }
        let coordinator = JobCoordinator(transport: InProcessWorkerTransport(), journal: root.appendingPathComponent("Jobs"))
        let model = AppModel(coordinator: coordinator, sounds: context.makeSounds())
        let source = try image(in: root)
        let choice = try XCTUnwrap(WheelChoice.common([AssetDescriptor(source: source, family: .image, format: "png", byteCount: 1)]).first { $0.profile.id == "jpg" })
        model.performWheel([source, root.appendingPathComponent("missing.png")], choice: choice)
        try await settle(model)
        XCTAssertEqual(model.jobs.filter { $0.state == .succeeded }.count, 1)
        XCTAssertEqual(model.jobs.filter { $0.state == .failed }.count, 1)
        XCTAssertTrue(context.playback.played.isEmpty)

        model.enqueue(OperationRequest(inputs: [], action: .imageConvert, profiles: [ActionCatalog.jpg]))
        try await settle(model)
        XCTAssertEqual(model.jobs.last?.state, .failed)
        XCTAssertTrue(context.playback.played.isEmpty)

        model.performWheel([source, source], choice: choice)
        model.cancel()
        try await settle(model)
        XCTAssertEqual(model.jobs.suffix(2).map(\.state), [.cancelled, .cancelled])
        XCTAssertFalse(model.isCancelling)
        XCTAssertTrue(context.playback.played.isEmpty)
        // A later successful action still confirms normally.
        model.performWheel([source], choice: choice); try await settle(model)
        XCTAssertEqual(context.playback.played, [.success])
    }

    @MainActor func testManualRecipeConfirmsButPreviewAndDirectCoordinatorJobsStaySilent() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let context = SoundTestContext(); defer { context.cleanUp() }
        let coordinator = JobCoordinator(transport: InProcessWorkerTransport(), journal: root.appendingPathComponent("Jobs"))
        let model = AppModel(coordinator: coordinator, sounds: context.makeSounds())
        let source = try image(in: root)
        model.setSources([source]); try await settle(model)
        model.selectAction(.imageConvert); model.selectedProfileID = "jpg"
        model.previewResult(); try await settle(model)
        XCTAssertNotNil(model.resultPreviewURL, model.message ?? "Preview returned no result")
        XCTAssertTrue(context.playback.played.isEmpty)
        model.cancelPreview()
        // Watchers and other background callers use the coordinator directly.
        _ = try await coordinator.run(OperationRequest(inputs: [source], action: .imageConvert, profiles: [ActionCatalog.jpg]))
        XCTAssertTrue(context.playback.played.isEmpty)
        let recipe = Recipe(name: "Two exports", steps: [
            .init(action: .imageConvert, profiles: [ActionCatalog.jpg], export: true),
            .init(action: .imagesToPDF, profiles: [ActionCatalog.pdf], export: true)
        ])
        model.runRecipe(recipe); try await settle(model)
        XCTAssertEqual(context.playback.played, [.success])
        model.runRecipe(Recipe(name: "Invalid", steps: [])); try await settle(model)
        XCTAssertEqual(context.playback.played, [.success])
    }

    @MainActor func testCancellationDuringWorkerExecutionNeverConfirms() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let context = SoundTestContext(); defer { context.cleanUp() }
        let transport = DelayedSoundTestTransport()
        let coordinator = JobCoordinator(transport: transport, journal: root.appendingPathComponent("Jobs"))
        let model = AppModel(coordinator: coordinator, sounds: context.makeSounds())
        model.enqueue(OperationRequest(inputs: [try image(in: root)], action: .imageConvert, profiles: [ActionCatalog.jpg]), showWindow: false)
        for _ in 0..<100 {
            if await transport.started { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        let started = await transport.started
        XCTAssertTrue(started)
        model.cancel(); try await settle(model)
        XCTAssertEqual(model.jobs.first?.state, .cancelled)
        XCTAssertTrue(context.playback.played.isEmpty)
    }
}

private actor DelayedSoundTestTransport: WorkerTransport {
    var started = false
    func perform(_ envelope: WorkerEnvelope) async throws -> WorkerResponse {
        started = true
        try await Task.sleep(nanoseconds: 5_000_000_000)
        return try await InProcessWorkerTransport().perform(envelope)
    }
}
