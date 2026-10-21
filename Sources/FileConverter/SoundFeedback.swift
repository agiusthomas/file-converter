import AVFoundation
import Combine
import Foundation

enum SoundCue: String, CaseIterable {
    case opening, tick, success

    static var resourceDirectory: URL? {
        #if SWIFT_PACKAGE
        return Bundle.module.resourceURL?.appendingPathComponent("Sounds/soft-detent")
        #else
        return Bundle.main.resourceURL?.appendingPathComponent("Sounds/soft-detent")
        #endif
    }
}

@MainActor protocol SoundPlayback: AnyObject {
    var volume: Float { get set }
    func play(_ cue: SoundCue)
    func stop(_ cue: SoundCue)
}

/// Missing assets or unavailable audio output are deliberately non-fatal.
@MainActor final class BundledSoundPlayback: SoundPlayback {
    private var players: [SoundCue: AVAudioPlayer] = [:]
    var volume: Float = 1.0 {
        didSet { players.values.forEach { $0.volume = volume } }
    }

    init(directory: URL? = SoundCue.resourceDirectory) {
        guard let directory else { return }
        for cue in SoundCue.allCases {
            guard let player = try? AVAudioPlayer(contentsOf: directory.appendingPathComponent(cue.rawValue + ".wav")) else { continue }
            player.volume = volume
            player.prepareToPlay()
            players[cue] = player
        }
    }

    func play(_ cue: SoundCue) {
        // A new cue replaces the previous one; fast gestures never build a queue.
        for cue in SoundCue.allCases { stop(cue) }
        players[cue]?.play()
    }

    func stop(_ cue: SoundCue) {
        players[cue]?.stop()
        players[cue]?.currentTime = 0
    }
}

@MainActor final class SoundFeedback: ObservableObject {
    @Published var enabled: Bool {
        didSet {
            defaults.set(enabled, forKey: "soundEffectsEnabled")
            if !enabled { stopAll() }
        }
    }
    @Published var volume: Double {
        didSet {
            let clamped = Self.clamped(volume)
            if volume != clamped { volume = clamped; return }
            defaults.set(volume, forKey: "soundEffectsVolume")
            playback.volume = Float(volume)
            if volume == 0 { stopAll() }
        }
    }
    private let defaults: UserDefaults
    private let playback: any SoundPlayback
    private let now: () -> TimeInterval
    private var wheelVisible = false
    private var nextTickAt: TimeInterval = 0
    private var previewTask: Task<Void, Never>?

    init(defaults: UserDefaults = .standard, playback: (any SoundPlayback)? = nil,
         now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        self.defaults = defaults
        self.playback = playback ?? BundledSoundPlayback()
        self.now = now
        defaults.register(defaults: ["soundEffectsEnabled": true, "soundEffectsVolume": 1.0])
        enabled = defaults.bool(forKey: "soundEffectsEnabled")
        volume = Self.clamped(defaults.double(forKey: "soundEffectsVolume"))
        self.playback.volume = Float(volume)
    }

    private static func clamped(_ value: Double) -> Double {
        value.isFinite ? min(1, max(0, value)) : 1.0
    }

    func wheelOpened() {
        cancelPreview()
        wheelVisible = true
        nextTickAt = now() + 0.08
        play(.opening)
    }

    func wheelOptionChanged() {
        guard wheelVisible, enabled, volume > 0, now() >= nextTickAt else { return }
        nextTickAt = now() + 0.06
        cancelPreview()
        play(.tick)
    }

    func wheelDismissed() {
        wheelVisible = false
        playback.stop(.opening)
        playback.stop(.tick)
    }

    func conversionSucceeded() {
        cancelPreview()
        nextTickAt = now() + 0.43
        play(.success)
    }

    func preview() {
        stopAll()
        guard enabled, volume > 0 else { return }
        previewTask = Task { [weak self] in
            guard !Task.isCancelled else { return }
            self?.play(.opening)
            // The same rhythm as the saved comparison preview, without its lead-in.
            let sequence: [(UInt64, SoundCue)] = [(630_000_000, .tick), (240_000_000, .tick),
                (240_000_000, .tick), (240_000_000, .tick), (240_000_000, .tick), (640_000_000, .success)]
            for (delay, cue) in sequence {
                do { try await Task.sleep(nanoseconds: delay) } catch { return }
                guard !Task.isCancelled else { return }
                self?.play(cue)
            }
            self?.previewTask = nil
        }
    }

    private func play(_ cue: SoundCue) {
        guard enabled, volume > 0 else { return }
        playback.play(cue)
    }

    private func cancelPreview() {
        guard previewTask != nil else { return }
        previewTask?.cancel(); previewTask = nil
        for cue in SoundCue.allCases { playback.stop(cue) }
    }

    private func stopAll() {
        cancelPreview()
        for cue in SoundCue.allCases { playback.stop(cue) }
    }
}

/// Tracks explicit user actions independently of queue drains and saved history.
struct ConversionSoundBatches {
    private struct Batch {
        var remaining: Set<UUID>
        var failed = false
    }
    private var batches: [UUID: Batch] = [:]
    private var batchForJob: [UUID: UUID] = [:]

    mutating func register(_ jobs: [UUID]) {
        guard !jobs.isEmpty else { return }
        let id = UUID()
        batches[id] = Batch(remaining: Set(jobs))
        for job in jobs { batchForJob[job] = id }
    }

    /// Returns true exactly once, and only if every job in the action succeeded.
    mutating func finish(_ job: UUID, succeeded: Bool) -> Bool {
        guard let id = batchForJob.removeValue(forKey: job), var batch = batches[id] else { return false }
        batch.remaining.remove(job)
        batch.failed = batch.failed || !succeeded
        if batch.remaining.isEmpty {
            batches.removeValue(forKey: id)
            return !batch.failed
        }
        batches[id] = batch
        return false
    }

    mutating func cancelAll() {
        batches.removeAll(); batchForJob.removeAll()
    }
}
