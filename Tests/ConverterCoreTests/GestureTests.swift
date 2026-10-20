import XCTest
@testable import ConverterCore

final class GestureTests: XCTestCase {
    private func sample(_ down: Bool, shift: Bool = false, escape: Bool = false, x: Double = 0, revision: Int = 10, files: Bool = true) -> DragSample {
        DragSample(mouseDown: down, shiftDown: shift, escapeDown: escape, x: x, y: 0, pasteboardRevision: revision, hasFiles: files)
    }
    func testShiftHeldBeforeDragActivatesOnceAndSurvivesModifierRelease() {
        var state = DragGestureState()
        XCTAssertNil(state.update(sample(false)))
        XCTAssertNil(state.update(sample(true, shift: true)))
        XCTAssertEqual(state.update(sample(true, shift: true, x: 12, revision: 11)), .showWheel)
        XCTAssertNil(state.update(sample(true, x: 30, revision: 11)))
        XCTAssertEqual(state.update(sample(false, revision: 11)), .releaseWheel)
    }
    func testShiftPressedDuringDragAndEscapeDoNotReactivateUntilNextDrag() {
        var state = DragGestureState()
        _ = state.update(sample(false))
        _ = state.update(sample(true))
        XCTAssertNil(state.update(sample(true, x: 12, revision: 11)))
        XCTAssertEqual(state.update(sample(true, shift: true, x: 12, revision: 11)), .showWheel)
        XCTAssertEqual(state.update(sample(true, shift: true, escape: true, x: 12, revision: 11)), .dismissWheel)
        XCTAssertNil(state.update(sample(true, shift: true, x: 20, revision: 11)))
        _ = state.update(sample(false, revision: 11))
        _ = state.update(sample(true, shift: true, revision: 11))
        XCTAssertEqual(state.update(sample(true, shift: true, x: 12, revision: 12)), .showWheel)
    }
    func testShiftClickAndStaleDragPasteboardDoNotActivate() {
        var state = DragGestureState()
        _ = state.update(sample(false))
        XCTAssertNil(state.update(sample(true, shift: true)))
        XCTAssertNil(state.update(sample(true, shift: true, x: 3, revision: 11)))
        _ = state.update(sample(false, revision: 11))
        _ = state.update(sample(true, shift: true, revision: 11))
        XCTAssertNil(state.update(sample(true, shift: true, x: 100, revision: 11)))
    }
    func testNonFileDragsDoNotActivate() {
        var state = DragGestureState()
        _ = state.update(sample(false, files: false))
        _ = state.update(sample(true, shift: true, files: false))
        XCTAssertNil(state.update(sample(true, shift: true, x: 100, revision: 11, files: false)))
    }
    func testReleaseOnlyCommitsOnceAndEscapeOnReleaseCancels() {
        for escape in [false, true] {
            var state = DragGestureState()
            _ = state.update(sample(false))
            _ = state.update(sample(true, shift: true))
            XCTAssertEqual(state.update(sample(true, shift: true, x: 12, revision: 11)), .showWheel)
            XCTAssertEqual(state.update(sample(false, escape: escape, x: 100, revision: 11)),
                           escape ? .dismissWheel : .releaseWheel)
            XCTAssertNil(state.update(sample(false, x: 100, revision: 11)))
        }
    }
    func testWheelHitTestingHasNeutralCentreOutsideAndSectorGaps() {
        let geometry = WheelGeometry(count: 8)
        XCTAssertEqual(geometry.sector(x: 0, y: 125), 0)
        XCTAssertEqual(geometry.sector(x: 125, y: 0), 2)
        XCTAssertEqual(geometry.sector(x: 0, y: -125), 4)
        XCTAssertNil(geometry.sector(x: 0, y: 20))
        XCTAssertNil(geometry.sector(x: 0, y: 200))
        let angle = Double.pi / 8
        XCTAssertNil(geometry.sector(x: sin(angle) * 125, y: cos(angle) * 125))
    }
    func testMixedSelectionUsesSharedRoutesAndRejectsUnknownFiles() {
        let registry = CapabilityRegistry(writableFormats: [.png, .jpeg, .tiff, .pdf])
        XCTAssertEqual(registry.destinations(for: [URL(fileURLWithPath: "/a.PNG"), URL(fileURLWithPath: "/b.jpeg")]), [.tiff, .pdf])
        XCTAssertTrue(registry.destinations(for: [URL(fileURLWithPath: "/a.png"), URL(fileURLWithPath: "/b.docx")]).isEmpty)
        XCTAssertTrue(registry.destinations(for: []).isEmpty)
    }
}
