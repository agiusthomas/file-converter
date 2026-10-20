import AppKit
import XCTest
import ConverterCore
@testable import FileConverter

final class WheelTrackingTests: XCTestCase {
    @MainActor private func withWheel(at origin: NSPoint, _ body: @MainActor (WheelView, NSWindow) -> Void) {
        _ = NSApplication.shared
        let formats = WheelChoice.common([
            AssetDescriptor(source: URL(fileURLWithPath: "/tmp/wheel.jpg"), family: .image, format: "jpg", byteCount: 1)
        ])
        let wheel = WheelView(frame: NSRect(x: 0, y: 0, width: 420, height: 420),
                              sources: [URL(fileURLWithPath: "/tmp/wheel.jpg")], formats: formats)
        let window = NSPanel(contentRect: NSRect(origin: origin, size: wheel.frame.size),
                             styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = wheel
        defer { window.close() }
        body(wheel, window)
    }

    @MainActor func testPointerSamplesTrackEverySectorWithoutDragCallbacks() async {
        // A display to the left/below the primary display has negative origins.
        for origin in [NSPoint(x: 300, y: 200), NSPoint(x: -1000, y: -600)] {
            withWheel(at: origin) { wheel, window in
                for _ in 0..<3 {
                    for index in wheel.formats.indices.reversed() {
                        let angle = Double(index) * 2 * .pi / Double(wheel.formats.count)
                        let local = NSPoint(x: 210 + sin(angle) * 126, y: 210 + cos(angle) * 126)
                        wheel.updateDragHighlight(at: window.convertPoint(toScreen: wheel.convert(local, to: nil)))
                        XCTAssertEqual(wheel.selected, index)
                    }
                }
            }
        }
    }

    @MainActor func testSoundFeedbackFollowsChangedOptionsAcrossPointerMouseAndKeyboard() async {
        let context = SoundTestContext(); defer { context.cleanUp() }
        var time = 10.0
        let sounds = context.makeSounds(now: { time })
        withWheel(at: NSPoint(x: 100, y: 100)) { wheel, window in
            wheel.onSelectionChanged = { sounds.wheelOptionChanged() }
            sounds.wheelOpened(); time += 0.1
            let top = window.convertPoint(toScreen: wheel.convert(NSPoint(x: 210, y: 336), to: nil))
            for _ in 0..<10 { wheel.updateDragHighlight(at: top) }
            XCTAssertEqual(context.playback.played, [.opening, .tick])
            time += 0.1
            wheel.updateDragHighlight(at: window.convertPoint(toScreen: NSPoint(x: 210, y: 210)))
            XCTAssertEqual(context.playback.played.count, 2)
            wheel.updateDragHighlight(at: top)
            XCTAssertEqual(context.playback.played.count, 3)
            time += 0.1
            let angle = 2 * Double.pi / Double(wheel.formats.count)
            let mousePoint = NSPoint(x: 210 + sin(angle) * 126, y: 210 + cos(angle) * 126)
            let mouse = NSEvent.mouseEvent(with: .mouseMoved, location: mousePoint, modifierFlags: [],
                timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 0, pressure: 0)!
            wheel.mouseMoved(with: mouse)
            XCTAssertEqual(wheel.selected, 1)
            XCTAssertEqual(context.playback.played.count, 4)
            time += 0.1
            let right = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                windowNumber: window.windowNumber, context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: 124)!
            wheel.keyDown(with: right)
            XCTAssertEqual(wheel.selected, 2)
            XCTAssertEqual(context.playback.played.count, 5)
            var choices = 0
            wheel.onChoose = { _, _ in choices += 1; sounds.wheelDismissed() }
            let enter = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                windowNumber: window.windowNumber, context: nil, characters: "\r", charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36)!
            wheel.keyDown(with: enter)
            time += 1
            wheel.completeDrag(at: top)
            XCTAssertEqual(choices, 1)
            XCTAssertEqual(context.playback.played.count, 5)
        }
    }

    @MainActor func testPointerLeavingSectorClearsHighlightAndCanReenter() async {
        withWheel(at: NSPoint(x: 100, y: 100)) { wheel, window in
            @MainActor func sample(_ point: NSPoint) {
                wheel.updateDragHighlight(at: window.convertPoint(toScreen: wheel.convert(point, to: nil)))
            }
            let boundary = .pi / Double(wheel.formats.count)
            for neutral in [NSPoint(x: 210, y: 210), NSPoint(x: 700, y: 210),
                            NSPoint(x: 210 + sin(boundary) * 126, y: 210 + cos(boundary) * 126)] {
                sample(NSPoint(x: 210, y: 336))
                XCTAssertEqual(wheel.selected, 0)
                sample(neutral)
                XCTAssertNil(wheel.selected)
            }
            sample(NSPoint(x: 210, y: 336))
            XCTAssertEqual(wheel.selected, 0)
        }
    }

    @MainActor func testReleaseStartsJPGConversionWithoutNativeDropCallback() async {
        for profileID in ["avif", "webp", "pdf"] {
            withWheel(at: NSPoint(x: 100, y: 100)) { wheel, window in
                guard let index = wheel.formats.firstIndex(where: { $0.profile.id == profileID }) else {
                    // AVIF is only offered on systems with an available encoder.
                    XCTAssertEqual(profileID, "avif")
                    return
                }
                let angle = Double(index) * 2 * .pi / Double(wheel.formats.count)
                let local = NSPoint(x: 210 + sin(angle) * 126, y: 210 + cos(angle) * 126)
                let release = window.convertPoint(toScreen: wheel.convert(local, to: nil))
                var choices: [WheelChoice] = []
                wheel.onChoose = { urls, choice in
                    XCTAssertEqual(urls, wheel.sources)
                    choices.append(choice)
                }
                // A stale hover must not determine the output on mouse-up.
                wheel.selected = (index + 1) % wheel.formats.count
                wheel.completeDrag(at: release)
                wheel.completeDrag(at: release)
                XCTAssertEqual(choices.map(\.profile.id), [profileID])
                XCTAssertEqual(choices.first?.action, profileID == "pdf" ? .imagesToPDF : .imageConvert)
            }
        }
    }

    @MainActor func testReleaseInCentreOrOutsideNeverChoosesStaleHighlight() async {
        for release in [NSPoint(x: 210, y: 210), NSPoint(x: 700, y: 210)] {
            withWheel(at: NSPoint(x: 100, y: 100)) { wheel, window in
                wheel.selected = 0
                wheel.onChoose = { _, _ in XCTFail("A neutral release must not start conversion") }
                wheel.completeDrag(at: window.convertPoint(toScreen: wheel.convert(release, to: nil)))
            }
        }
    }

    @MainActor func testNativeDropAndPolledReleaseCannotSubmitTwice() async {
        for nativeFirst in [true, false] {
            withWheel(at: NSPoint(x: 100, y: 100)) { wheel, window in
                let pasteboard = NSPasteboard.withUniqueName()
                defer { pasteboard.releaseGlobally() }
                pasteboard.writeObjects(wheel.sources.map { $0 as NSURL })
                let local = NSPoint(x: 210, y: 336)
                let windowPoint = wheel.convert(local, to: nil)
                let release = window.convertPoint(toScreen: windowPoint)
                let info = TestDraggingInfo(window: window, pasteboard: pasteboard, location: windowPoint)
                var submissions = 0
                wheel.onChoose = { _, _ in submissions += 1 }
                if nativeFirst {
                    XCTAssertTrue(wheel.performDragOperation(info))
                    wheel.completeDrag(at: release)
                } else {
                    wheel.completeDrag(at: release)
                    _ = wheel.performDragOperation(info)
                }
                XCTAssertEqual(submissions, 1)
            }
        }
    }

    @MainActor func testControllerReleaseWithoutNativeDropCallback() async throws {
        guard ProcessInfo.processInfo.environment["FILE_CONVERTER_WHEEL_TESTS"] == "1" else {
            throw XCTSkip("Set FILE_CONVERTER_WHEEL_TESTS=1 with access to the macOS window server.")
        }
        _ = NSApplication.shared
        let controller = WheelPanelController()
        let soundContext = SoundTestContext(); defer { soundContext.cleanUp() }
        controller.sounds = soundContext.makeSounds()
        defer { controller.dismiss() }
        let source = URL(fileURLWithPath: "/tmp/wheel-release.jpg")
        controller.inspect = { urls in
            [AssetDescriptor(source: urls[0], family: .image, format: "jpg", byteCount: 1)]
        }
        let converted = expectation(description: "Release starts conversion without an AppKit drop")
        converted.assertForOverFulfill = true
        controller.onConversion = { urls, choice in
            XCTAssertEqual(urls, [source])
            XCTAssertEqual(choice.profile.id, "webp")
            converted.fulfill()
        }
        controller.show(sources: [source], at: NSEvent.mouseLocation)
        for _ in 0..<100 {
            if controller.panel != nil { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        let panel = try XCTUnwrap(controller.panel)
        XCTAssertEqual(soundContext.playback.played, [.opening])
        let wheel = try XCTUnwrap(panel.contentView as? WheelView)
        // Allow the window server to commit the new panel before hit testing.
        try await Task.sleep(nanoseconds: 150_000_000)
        let index = try XCTUnwrap(wheel.formats.firstIndex { $0.profile.id == "webp" })
        let angle = Double(index) * 2 * .pi / Double(wheel.formats.count)
        let local = NSPoint(x: 210 + sin(angle) * 126, y: 210 + cos(angle) * 126)
        let release = panel.convertPoint(toScreen: wheel.convert(local, to: nil))
        panel.displayIfNeeded()
        XCTAssertEqual(NSWindow.windowNumber(at: release, belowWindowWithWindowNumber: 0), panel.windowNumber,
                       "The visible wheel must receive drops instead of passing them to the window behind it")
        controller.releaseDrag(at: release)
        await fulfillment(of: [converted], timeout: 2)
        XCTAssertNil(controller.panel)
    }
}

@MainActor private final class TestDraggingInfo: NSObject, NSDraggingInfo {
    let draggingDestinationWindow: NSWindow?
    let draggingPasteboard: NSPasteboard
    let draggingLocation: NSPoint
    let draggingSourceOperationMask: NSDragOperation = .copy
    let draggedImageLocation = NSPoint.zero
    let draggedImage: NSImage? = nil
    let draggingSource: Any? = nil
    let draggingSequenceNumber = 1
    var draggingFormation: NSDraggingFormation = .none
    var animatesToDestination = false
    var numberOfValidItemsForDrop = 1
    let springLoadingHighlight: NSSpringLoadingHighlight = .none
    init(window: NSWindow, pasteboard: NSPasteboard, location: NSPoint) {
        draggingDestinationWindow = window; draggingPasteboard = pasteboard; draggingLocation = location
    }
    func slideDraggedImage(to screenPoint: NSPoint) {}
    nonisolated override func namesOfPromisedFilesDropped(atDestination dropDestination: URL) -> [String]? { nil }
    func resetSpringLoading() {}
    func enumerateDraggingItems(options enumOpts: NSDraggingItemEnumerationOptions = [], for view: NSView?,
                                classes classArray: [AnyClass], searchOptions: [NSPasteboard.ReadingOptionKey: Any] = [:],
                                using block: (NSDraggingItem, Int, UnsafeMutablePointer<ObjCBool>) -> Void) {}
}
