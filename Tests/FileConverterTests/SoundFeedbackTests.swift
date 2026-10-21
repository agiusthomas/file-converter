import AppKit
import AVFoundation
import XCTest
@testable import FileConverter

@MainActor final class SoundPlaybackSpy: SoundPlayback {
    var volume: Float = 0
    var played: [SoundCue] = []
    var stopped: [SoundCue] = []
    var onPlay: ((SoundCue) -> Void)?
    func play(_ cue: SoundCue) { played.append(cue); onPlay?(cue) }
    func stop(_ cue: SoundCue) { stopped.append(cue) }
}

@MainActor struct SoundTestContext {
    let name = "SoundFeedbackTests.\(UUID().uuidString)"
    let defaults: UserDefaults
    let playback = SoundPlaybackSpy()
    init() { defaults = UserDefaults(suiteName: name)! }
    func makeSounds(now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) -> SoundFeedback {
        SoundFeedback(defaults: defaults, playback: playback, now: now)
    }
    func cleanUp() { defaults.removePersistentDomain(forName: name) }
}

final class SoundFeedbackTests: XCTestCase {
    @MainActor func testTickRateLimitDiscardsRapidEventsAndDismissalStopsWheelCues() async {
        let context = SoundTestContext(); defer { context.cleanUp() }
        var time = 10.0
        let sounds = context.makeSounds(now: { time })
        sounds.wheelOptionChanged()
        XCTAssertTrue(context.playback.played.isEmpty)
        sounds.wheelOpened()
        sounds.wheelOptionChanged()
        time += 0.09
        sounds.wheelOptionChanged()
        for _ in 0..<20 { time += 0.001; sounds.wheelOptionChanged() }
        XCTAssertEqual(context.playback.played, [.opening, .tick])
        time += 0.1
        sounds.wheelOptionChanged()
        sounds.wheelDismissed()
        time += 1
        sounds.wheelOptionChanged()
        XCTAssertEqual(context.playback.played, [.opening, .tick, .tick])
        XCTAssertTrue(context.playback.stopped.contains(.opening))
        XCTAssertTrue(context.playback.stopped.contains(.tick))
        // No discarded movement is played later.
        await Task.yield()
        XCTAssertEqual(context.playback.played.count, 3)
    }

    @MainActor func testPreferencesPersistAndMuteAppliesToEveryCue() async {
        let context = SoundTestContext(); defer { context.cleanUp() }
        let sounds = context.makeSounds()
        XCTAssertTrue(sounds.enabled)
        XCTAssertEqual(sounds.volume, 1.0)
        sounds.volume = 0.6
        XCTAssertEqual(context.playback.volume, 0.6, accuracy: 0.001)
        sounds.enabled = false
        sounds.wheelOpened(); sounds.wheelOptionChanged(); sounds.conversionSucceeded(); sounds.preview()
        await Task.yield()
        XCTAssertTrue(context.playback.played.isEmpty)
        XCTAssertEqual(Set(context.playback.stopped), Set(SoundCue.allCases))
        let restored = context.makeSounds()
        XCTAssertFalse(restored.enabled)
        XCTAssertEqual(restored.volume, 0.6)
        restored.enabled = true; restored.volume = 0
        restored.wheelOpened(); restored.conversionSucceeded(); restored.preview()
        await Task.yield()
        XCTAssertTrue(context.playback.played.isEmpty)
        restored.volume = 2
        XCTAssertEqual(restored.volume, 1)
        restored.volume = .nan
        XCTAssertEqual(restored.volume, 1.0)
    }

    @MainActor func testPreviewPlaysWholeSequenceAndMuteCancelsPendingSounds() async throws {
        let context = SoundTestContext(); defer { context.cleanUp() }
        let sounds = context.makeSounds()
        let completed = expectation(description: "Preview reaches its success cue")
        context.playback.onPlay = { cue in
            if cue == .success { completed.fulfill() }
        }
        sounds.preview()
        await fulfillment(of: [completed], timeout: 10)
        context.playback.onPlay = nil
        XCTAssertEqual(context.playback.played, [.opening, .tick, .tick, .tick, .tick, .tick, .success])
        sounds.preview()
        await Task.yield()
        XCTAssertEqual(context.playback.played.last, .opening)
        let count = context.playback.played.count
        sounds.enabled = false
        try await Task.sleep(nanoseconds: 700_000_000)
        XCTAssertEqual(context.playback.played.count, count)
    }

    @MainActor func testSuccessInterruptsPreviewAndSuppressesTicksDuringItsTail() async throws {
        let context = SoundTestContext(); defer { context.cleanUp() }
        var time = 10.0
        let sounds = context.makeSounds(now: { time })
        sounds.wheelOpened()
        sounds.preview()
        await Task.yield()
        sounds.conversionSucceeded()
        time += 0.1; sounds.wheelOptionChanged()
        XCTAssertEqual(context.playback.played.last, .success)
        let count = context.playback.played.count
        try await Task.sleep(nanoseconds: 700_000_000)
        XCTAssertEqual(context.playback.played.count, count)
        time += 0.4; sounds.wheelOptionChanged()
        XCTAssertEqual(context.playback.played.last, .tick)
    }

    @MainActor func testPreviewCancelledBeforeStartingCannotReplaceSuccess() async {
        let context = SoundTestContext(); defer { context.cleanUp() }
        let sounds = context.makeSounds()
        sounds.preview()
        sounds.conversionSucceeded()
        await Task.yield()
        XCTAssertEqual(context.playback.played, [.success])
    }

    @MainActor func testBundledCuesDecodeAndMissingResourcesAreHarmless() async throws {
        let directory = try XCTUnwrap(SoundCue.resourceDirectory)
        for cue in SoundCue.allCases {
            let audio = try AVAudioFile(forReading: directory.appendingPathComponent(cue.rawValue + ".wav"))
            XCTAssertEqual(audio.fileFormat.channelCount, 1)
            XCTAssertEqual(audio.fileFormat.sampleRate, 32000)
            XCTAssertGreaterThan(audio.length, 0)
            XCTAssertLessThan(Double(audio.length) / audio.fileFormat.sampleRate, 0.5)
        }
        let missing = BundledSoundPlayback(directory: directory.appendingPathComponent("missing"))
        missing.play(.opening); missing.play(.tick); missing.play(.success)
    }

    func testBatchesConfirmIndependentlyAndNeverConfirmFailuresOrDuplicates() {
        var batches = ConversionSoundBatches()
        let a = UUID(), b = UUID(), c = UUID(), d = UUID(), e = UUID()
        batches.register([a, b]); batches.register([c])
        XCTAssertFalse(batches.finish(a, succeeded: true))
        XCTAssertTrue(batches.finish(c, succeeded: true))
        XCTAssertTrue(batches.finish(b, succeeded: true))
        XCTAssertFalse(batches.finish(b, succeeded: true))
        batches.register([d, e])
        XCTAssertFalse(batches.finish(d, succeeded: false))
        XCTAssertFalse(batches.finish(e, succeeded: true))
        batches.register([UUID(), a]); batches.cancelAll()
        XCTAssertFalse(batches.finish(a, succeeded: true))
    }
}
