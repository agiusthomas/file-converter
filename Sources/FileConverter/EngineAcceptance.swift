import AppKit
import ConverterCore

/// Opt-in release qualification from the signed app executable. Uses the same
/// coordinator, pack verification, staging, XPC service and publication as the UI.
/// No injected adapter, process transport or trust override is permitted here.
@MainActor enum EngineAcceptance {
    struct Configuration: Decodable {
        var pack: URL
        var update: URL?
        var audio: URL
        var video: URL
        var cancellation: URL
        var downloadUpdate: Bool?
    }
    static func run(in root: URL) async {
        var report: [String:Any] = ["appVersion":EnginePacks.appVersion, "transport":"XPCWorkerTransport", "passed":false]
        let reportURL = root.appendingPathComponent("report.json")
        func save() {
            if let data = try? JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]) { try? data.write(to:reportURL,options:.atomic) }
        }
        do {
            guard Bundle.main.bundleURL.pathExtension == "app" else { throw OperationFailure.verification("Run qualification from the signed app bundle.") }
            report["team"] = try EnginePacks.signingTeam(EnginePacks.publisherCodeURL)
            let config = try JSONDecoder().decode(Configuration.self,from:Data(contentsOf:root.appendingPathComponent("configuration.json")))
            let store = EnginePacks.executableRoot.appendingPathComponent("Acceptance-\(root.lastPathComponent)",isDirectory:true)
            report["isolatedEngineStore"] = store.path
            let first = try EnginePacks.install(config.pack,root:store)
            report["firstVersion"] = first.manifest.version
            let tampered = root.appendingPathComponent("Tampered.bundle")
            try FileManager.default.copyItem(at:config.pack,to:tampered)
            defer { try? FileManager.default.removeItem(at:tampered) }
            guard let tool = first.manifest.tools["ffprobe"] else { throw OperationFailure.verification("Missing probe.") }
            let altered = try FileHandle(forWritingTo:tampered.appendingPathComponent(tool))
            try altered.seekToEnd(); try altered.write(contentsOf:Data("tamper".utf8)); try altered.close()
            do { _ = try EnginePacks.install(tampered,root:store); throw OperationFailure.process("Tampered update was accepted.") }
            catch OperationFailure.verification { report["tamperRejected"] = true }
            guard try String(contentsOf:store.appendingPathComponent("media.current"),encoding:.utf8) == first.location.lastPathComponent else { throw OperationFailure.verification("Failed update changed the active version.") }
            let coordinator = JobCoordinator(transport:XPCWorkerTransport(),journal:root.appendingPathComponent("Jobs"),packs:[first])
            var originals: [String:String] = [:]
            for url in [config.audio,config.video,config.cancellation] { originals[url.path] = try FileDigest.sha256(url) }
            let output = root.appendingPathComponent("Outputs",isDirectory:true)
            try FileManager.default.createDirectory(at:output,withIntermediateDirectories:true)
            let flac = OutputProfile("flac","FLAC","flac",audioCodec:"flac")
            let audio = try await coordinator.run(.init(inputs:[config.audio],action:.mediaConvert,profiles:[flac],destination:output))
            guard audio.engine == "media" else { throw OperationFailure.verification("Audio did not execute in the Media pack.") }
            report["audio"] = try JSONSerialization.jsonObject(with:JSONEncoder().encode(audio)); save()
            let video = try await coordinator.run(.init(inputs:[config.video],action:.mediaConvert,profiles:[ActionCatalog.mp4],destination:output))
            guard video.engine == "media" else { throw OperationFailure.verification("Video did not execute in the Media pack.") }
            report["video"] = try JSONSerialization.jsonObject(with:JSONEncoder().encode(video)); save()
            if let update = config.update {
                let second: InstalledEnginePack
                if config.downloadUpdate == true {
                    guard let entry = try EnginePacks.catalog().first(where:{$0.id == "media"}) else { throw OperationFailure.verification("No sealed Media download entry.") }
                    let pointer = try Data(contentsOf:store.appendingPathComponent("media.current"))
                    let latch = DownloadCancellationLatch()
                    let interrupted = Task {
                        try await EnginePacks.download(entry,root:store) { progress in
                            if progress.phase == .downloading, progress.receivedBytes > 0, progress.receivedBytes < progress.totalBytes { latch.cancel(after:progress.receivedBytes) }
                        }
                    }
                    latch.bind(interrupted)
                    do { _ = try await interrupted.value; throw OperationFailure.verification("Interrupted download activated instead of cancelling.") }
                    catch is CancellationError { }
                    latch.clear()
                    guard latch.received > 0, try Data(contentsOf:store.appendingPathComponent("media.current")) == pointer else { throw OperationFailure.verification("Interrupted download changed the active runtime.") }
                    report["interruptedDownloadBytes"] = latch.received
                    report["interruptedDownloadPreservedRuntime"] = true
                    let progressURL = root.appendingPathComponent("download-progress.json")
                    second = try await EnginePacks.download(entry,root:store) { progress in
                        let data = try? JSONSerialization.data(withJSONObject:["phase":progress.phase.rawValue,"receivedBytes":progress.receivedBytes,"totalBytes":progress.totalBytes],options:[.sortedKeys])
                        try? data?.write(to:progressURL,options:.atomic)
                    }
                    report["downloadedFromSealedCatalog"] = entry.url.absoluteString
                } else { second = try EnginePacks.install(update,root:store) }
                guard second.manifest.engineVersions["ffmpeg"] != first.manifest.engineVersions["ffmpeg"] else { throw OperationFailure.verification("Update must use a different actual FFmpeg version.") }
                let rollbackPointer = try Data(contentsOf:store.appendingPathComponent("media.previous"))
                _ = try EnginePacks.install(update,root:store)
                guard try Data(contentsOf:store.appendingPathComponent("media.previous")) == rollbackPointer else { throw OperationFailure.verification("Retrying an install destroyed its rollback pointer.") }
                report["reinstallPreservedRollback"] = true
                let updated = JobCoordinator(transport:XPCWorkerTransport(),journal:root.appendingPathComponent("UpdateJobs"),packs:[second])
                let updatedAudio = try await updated.run(.init(inputs:[config.audio],action:.mediaConvert,profiles:[flac],destination:output))
                guard updatedAudio.engineVersions?["media/pack"] == second.manifest.version else { throw OperationFailure.verification("Updated runtime was not executed.") }
                report["updatedAudio"] = try JSONSerialization.jsonObject(with:JSONEncoder().encode(updatedAudio))
                let updatedVideo = try await updated.run(.init(inputs:[config.video],action:.mediaConvert,profiles:[ActionCatalog.mp4],destination:output))
                report["updatedVideo"] = try JSONSerialization.jsonObject(with:JSONEncoder().encode(updatedVideo))
                try EnginePacks.rollback("media",root:store)
                guard try String(contentsOf:store.appendingPathComponent("media.current"),encoding:.utf8) == first.location.lastPathComponent else { throw OperationFailure.verification("Rollback did not select the original runtime.") }
                report["updateVersion"] = second.manifest.version; report["rollback"] = true
            }
            // Remove the active pointer while this coordinator still pins its
            // immutable version. Cancellation below must still launch that pack.
            try EnginePacks.requestRemoval("media",root:store)
            guard try EnginePacks.collectRemovals(root:store).contains("media") else { throw OperationFailure.verification("Removal did not respect the live coordinator's runtime pin.") }
            report["removalDeferredForPin"] = true
            guard FileManager.default.fileExists(atPath:first.location.path) else { throw OperationFailure.verification("Deactivation removed a pinned runtime.") }
            let cancelOutput = root.appendingPathComponent("Cancelled",isDirectory:true)
            try FileManager.default.createDirectory(at:cancelOutput,withIntermediateDirectories:true)
            let request = OperationRequest(inputs:[config.cancellation],action:.mediaConvert,profiles:[OutputProfile("gif","Animated GIF","gif")],destination:cancelOutput)
            let finished = root.appendingPathComponent("cancellation-finished")
            let task = Task {
                defer { try? Data().write(to:finished) }
                return try await coordinator.run(request)
            }
            try Data(request.id.uuidString.utf8).write(to:root.appendingPathComponent("cancellation-ready"))
            // The external runner signals only after observing the real FFmpeg
            // child under this XPC worker. A timer alone would allow a false pass
            // by cancelling during verification before the engine ever launched.
            let deadline = Date().addingTimeInterval(60)
            while !FileManager.default.fileExists(atPath:root.appendingPathComponent("cancel-now").path) && !FileManager.default.fileExists(atPath:finished.path) && Date() < deadline {
                try await Task.sleep(nanoseconds:50_000_000)
            }
            task.cancel()
            do { _ = try await task.value; throw OperationFailure.verification("Cancellation job completed instead of cancelling.") }
            catch is CancellationError { }
            guard Date() < deadline else { throw OperationFailure.verification("No observed FFmpeg cancellation signal arrived.") }
            let records = try await coordinator.records()
            guard records.first(where:{$0.id == request.id})?.state == .cancelled,
                  try FileManager.default.contentsOfDirectory(atPath:cancelOutput.path).isEmpty else { throw OperationFailure.verification("Cancelled job published output or failed to record cancellation.") }
            for (path,hash) in originals { guard try FileDigest.sha256(URL(fileURLWithPath:path)) == hash else { throw OperationFailure.verification("An original changed.") } }
            report["originalsUnchanged"] = true; report["cancellation"] = true
            report["deactivatedPinnedRuntimeUsable"] = true
            guard try await coordinator.refreshPacks([]), try EnginePacks.collectRemovals(root:store).isEmpty,
                  !FileManager.default.fileExists(atPath:first.location.path) else { throw OperationFailure.verification("Retired runtime was not reclaimed after its final pin was released.") }
            report["removalReclaimedAfterRelease"] = true
            report["passed"] = true
        } catch { report["error"] = error.localizedDescription }
        save()
        NSApplication.shared.terminate(nil)
    }
}

private final class DownloadCancellationLatch: @unchecked Sendable {
    private let lock = NSLock()
    private var task: Task<InstalledEnginePack,Error>?
    private var bytes: Int64 = 0
    var received: Int64 { lock.lock(); defer { lock.unlock() }; return bytes }
    func bind(_ task: Task<InstalledEnginePack,Error>) { lock.lock(); self.task = task; let cancel = bytes > 0; lock.unlock(); if cancel { task.cancel() } }
    func cancel(after received: Int64) { lock.lock(); if bytes == 0 { bytes = received }; let task = task; lock.unlock(); task?.cancel() }
    func clear() { lock.lock(); task = nil; lock.unlock() }
}
