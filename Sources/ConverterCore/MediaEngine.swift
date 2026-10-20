import Foundation
@preconcurrency import AVFoundation
import AudioToolbox

public enum MediaEngine {
    public static func export(_ inputs: [URL], to output: URL, profile: OutputProfile, options: OperationOptions, join: Bool = false) async throws -> [String] {
        guard !options.normalizeLoudness else { throw OperationFailure.unsupported("Loudness normalization requires the Media pack.") }
        if profile.id == "wav" { guard inputs.count == 1, options.speed == 1 else { throw OperationFailure.unsupported("WAV export supports one source at normal speed.") }; try await wave(inputs[0], to:output, options:options); return [] }
        let composition = AVMutableComposition()
        let video = composition.addMutableTrack(withMediaType:.video,preferredTrackID:kCMPersistentTrackID_Invalid)
        let audio = composition.addMutableTrack(withMediaType:.audio,preferredTrackID:kCMPersistentTrackID_Invalid)
        var insertion = CMTime.zero; var signature: CGSize?; var transformSignature: CGAffineTransform?; var naturalSize: CGSize?; var frameRate: Float = 30; var notices: [String] = []
        for input in inputs {
            let asset = AVURLAsset(url:input); let duration = try await asset.load(.duration)
            let seconds = duration.seconds
            guard seconds.isFinite, seconds > options.startTime else { throw OperationFailure.invalidOptions("Trim start lies outside the media.") }
            let end = min(options.endTime ?? seconds, seconds)
            guard end > options.startTime else { throw OperationFailure.invalidOptions("The trim range is empty.") }
            let range = CMTimeRange(start:CMTime(seconds:options.startTime,preferredTimescale:600),end:CMTime(seconds:end,preferredTimescale:600))
            let tracks = try await asset.load(.tracks)
            let videoTracks = tracks.filter { $0.mediaType == .video }, audioTracks = tracks.filter { $0.mediaType == .audio }
            if videoTracks.count > 1 || audioTracks.count > 1 || tracks.contains(where: { ![.audio,.video].contains($0.mediaType) }) {
                throw OperationFailure.unsupported("This file has additional tracks. Select tracks using the Media pack to avoid silently discarding them.")
            }
            if let source = videoTracks.first, profile.videoCodec != nil {
                let size = try await source.load(.naturalSize); let transform = try await source.load(.preferredTransform)
                let displayed = size.applying(transform)
                let absolute = CGSize(width:abs(displayed.width),height:abs(displayed.height))
                if let signature, signature != absolute { throw OperationFailure.unsupported("Joined videos must have matching displayed dimensions.") }
                if let transformSignature, transformSignature != transform { throw OperationFailure.unsupported("Joined videos must have matching orientation transforms.") }
                signature = absolute; transformSignature = transform; naturalSize = size
                frameRate = try await source.load(.nominalFrameRate)
                try video?.insertTimeRange(range,of:source,at:insertion); video?.preferredTransform = transform
            }
            if !options.mute, let source = audioTracks.first { try audio?.insertTimeRange(range,of:source,at:insertion) }
            insertion = insertion + range.duration
        }
        for track in composition.tracks where track.segments.isEmpty { composition.removeTrack(track) }
        if options.mute, profile.videoCodec == nil { throw OperationFailure.invalidOptions("An audio-only output cannot be muted.") }
        if options.speed != 1 { composition.scaleTimeRange(CMTimeRange(start:.zero,duration:insertion),toDuration:CMTimeMultiplyByFloat64(insertion,multiplier:1/options.speed)) }
        if profile.id == "m4a-aac", !options.streamCopy {
            try await encodeAudio(composition,to:output,profile:profile,options:options,start:0,end:insertion.seconds/options.speed)
            return ["Audio was re-encoded as AAC with the chosen channels, sample rate, and bitrate."]
        }
        let preset: String
        if options.streamCopy {
            guard options.speed == 1, options.maximumDimension == nil, options.targetBytes == nil, options.crop == nil, options.rotation == 0 else { throw OperationFailure.invalidOptions("Stream copy cannot resize, change speed, or target a new size.") }
            preset = AVAssetExportPresetPassthrough
        } else if profile.videoCodec == nil { preset = AVAssetExportPresetAppleM4A }
        else if profile.videoCodec == "hevc" { preset = AVAssetExportPresetHEVCHighestQuality }
        else { preset = AVAssetExportPresetHighestQuality }
        guard let session = AVAssetExportSession(asset:composition,presetName:preset) else { throw OperationFailure.unsupported("This media cannot use the selected export profile.") }
        let type: AVFileType = profile.videoCodec == nil ? .m4a : .mp4
        guard session.supportedFileTypes.contains(type) else { throw OperationFailure.unsupported("The requested container is not supported for this media.") }
        session.outputURL = output; session.outputFileType = type; session.shouldOptimizeForNetworkUse = true
        if let video, let naturalSize, let preferred = transformSignature,
           options.maximumDimension != nil || options.crop != nil || options.rotation != 0 {
            let bounds = CGRect(origin:.zero,size:naturalSize).applying(preferred)
            var transform = preferred.concatenating(CGAffineTransform(translationX:-bounds.minX,y:-bounds.minY))
            var size = CGSize(width:abs(bounds.width),height:abs(bounds.height))
            if let crop = options.crop {
                guard crop.x + crop.width <= Int(size.width), crop.y + crop.height <= Int(size.height) else { throw OperationFailure.invalidOptions("Crop lies outside the displayed video.") }
                transform = transform.concatenating(CGAffineTransform(translationX:-CGFloat(crop.x),y:-CGFloat(crop.y)))
                size = CGSize(width:crop.width,height:crop.height)
            }
            let rotation = CGAffineTransform(rotationAngle:CGFloat(options.rotation % 360) * .pi / 180)
            let rotated = CGRect(origin:.zero,size:size).applying(rotation)
            transform = transform.concatenating(rotation).concatenating(CGAffineTransform(translationX:-rotated.minX,y:-rotated.minY))
            size = CGSize(width:abs(rotated.width),height:abs(rotated.height))
            let scale = options.maximumDimension.map { min(1,CGFloat($0)/max(size.width,size.height)) } ?? 1
            let rendered = CGSize(width:max(2,floor(size.width*scale/2)*2),height:max(2,floor(size.height*scale/2)*2))
            transform = transform.concatenating(CGAffineTransform(scaleX:rendered.width/size.width,y:rendered.height/size.height))
            let layer = AVMutableVideoCompositionLayerInstruction(assetTrack:video); layer.setTransform(transform,at:.zero)
            let instruction = AVMutableVideoCompositionInstruction(); instruction.timeRange = CMTimeRange(start:.zero,duration:composition.duration); instruction.layerInstructions = [layer]
            let videoComposition = AVMutableVideoComposition(); videoComposition.renderSize = rendered; videoComposition.frameDuration = CMTime(value:1,timescale:CMTimeScale(max(1,min(120,frameRate.rounded())))); videoComposition.instructions = [instruction]
            video.preferredTransform = .identity; session.videoComposition = videoComposition
        }
        if let target = options.targetBytes { session.fileLengthLimit = target }
        let exportHandle = MediaExportHandle(session)
        try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void,Error>) in
                exportHandle.session.exportAsynchronously {
                    if exportHandle.session.status == .completed { continuation.resume() }
                    else if exportHandle.session.status == .cancelled { continuation.resume(throwing:CancellationError()) }
                    else { continuation.resume(throwing:exportHandle.session.error ?? OperationFailure.process("Media export failed.")) }
                }
            }
        }, onCancel: { exportHandle.session.cancelExport() })
        try Task.checkCancellation()
        let result = AVURLAsset(url:output); let resultDuration = try await result.load(.duration).seconds
        let expected = insertion.seconds / options.speed
        guard resultDuration.isFinite, abs(resultDuration - expected) < max(0.25,expected * 0.005) else { throw OperationFailure.verification("Media duration changed unexpectedly.") }
        if let target = options.targetBytes, Int64(try output.resourceValues(forKeys:[.fileSizeKey]).fileSize ?? 0) > target { throw OperationFailure.invalidOptions("The requested size could not be reached. Allow a lower resolution or a larger file.") }
        if let limit = options.maximumDimension {
            let tracks = try await result.loadTracks(withMediaType:.video)
            if let track = tracks.first { let size = try await track.load(.naturalSize); guard max(size.width,size.height) <= CGFloat(max(2,limit)) else { throw OperationFailure.verification("The exported video exceeded the chosen dimensions.") } }
        }
        if profile.videoCodec != nil && !options.streamCopy { notices.append("Native movie export uses automatic audio settings. Install the Media pack for exact movie audio bitrate, sample rate, and channel controls.") }
        if options.streamCopy { notices.append("Compatible tracks copied without re-encoding.") }
        else { notices.append("Media was re-encoded. HDR, metadata, and channel layouts may change; inspect the result before sharing.") }
        return notices
    }
    public static func frame(_ input: URL, time: Double) async throws -> CGImage {
        let asset = AVURLAsset(url:input); let duration = try await asset.load(.duration).seconds
        guard time >= 0, time < duration else { throw OperationFailure.invalidOptions("Frame time lies outside the video.") }
        let generator = AVAssetImageGenerator(asset:asset); generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width:8192,height:8192)
        return try generator.copyCGImage(at:CMTime(seconds:time,preferredTimescale:600),actualTime:nil)
    }
    private static func wave(_ input: URL, to output: URL, options: OperationOptions) async throws {
        guard !options.mute else { throw OperationFailure.invalidOptions("An audio output cannot be muted.") }
        let asset = AVURLAsset(url:input)
        let duration = try await asset.load(.duration).seconds
        try await encodeAudio(asset,to:output,profile:ActionCatalog.wav,options:options,start:options.startTime,end:min(options.endTime ?? duration,duration))
    }
    private static func encodeAudio(_ asset: AVAsset, to output: URL, profile: OutputProfile, options: OperationOptions, start: Double, end: Double) async throws {
        let tracks = try await asset.loadTracks(withMediaType:.audio)
        guard tracks.count == 1 else { throw OperationFailure.unsupported("Audio export needs exactly one audio track.") }
        guard end.isFinite, end > start else { throw OperationFailure.invalidOptions("Invalid audio trim range.") }
        let reader = try AVAssetReader(asset:asset)
        reader.timeRange = CMTimeRange(start:CMTime(seconds:start,preferredTimescale:600),end:CMTime(seconds:end,preferredTimescale:600))
        let settings: [String:Any] = [AVFormatIDKey:kAudioFormatLinearPCM,AVSampleRateKey:options.sampleRate,AVNumberOfChannelsKey:options.channels,AVLinearPCMBitDepthKey:16,AVLinearPCMIsFloatKey:false,AVLinearPCMIsBigEndianKey:false,AVLinearPCMIsNonInterleaved:false]
        let source = AVAssetReaderTrackOutput(track:tracks[0],outputSettings:settings)
        guard reader.canAdd(source) else { throw OperationFailure.unsupported("Cannot decode the selected audio.") }; reader.add(source)
        let writer = try AVAssetWriter(outputURL:output,fileType:profile.id == "wav" ? .wav : .m4a)
        let encoded: [String:Any] = profile.id == "wav" ? settings : [AVFormatIDKey:kAudioFormatMPEG4AAC,AVSampleRateKey:options.sampleRate,AVNumberOfChannelsKey:options.channels,AVEncoderBitRateKey:options.bitrate]
        let sink = AVAssetWriterInput(mediaType:.audio,outputSettings:encoded)
        guard writer.canAdd(sink) else { throw OperationFailure.unsupported("Cannot encode WAV on this Mac.") }; writer.add(sink)
        guard writer.startWriting(),reader.startReading() else { throw OperationFailure.process("Cannot start audio conversion.") }
        writer.startSession(atSourceTime:reader.timeRange.start)
        do {
            while let sample = source.copyNextSampleBuffer() {
                try Task.checkCancellation()
                while !sink.isReadyForMoreMediaData { try await Task.sleep(nanoseconds:10_000_000); guard writer.status == .writing else { throw writer.error ?? OperationFailure.process("WAV writer stopped.") } }
                guard sink.append(sample) else { throw writer.error ?? OperationFailure.process("Cannot write WAV samples.") }
            }
            guard reader.status == .completed else { throw reader.error ?? OperationFailure.process("Audio decoding failed.") }
            sink.markAsFinished(); await writer.finishWriting()
            guard writer.status == .completed else { throw writer.error ?? OperationFailure.verification("WAV export failed.") }
        } catch { reader.cancelReading(); writer.cancelWriting(); throw error }
        let reopened = AVURLAsset(url:output)
        guard try await reopened.loadTracks(withMediaType:.audio).count == 1 else { throw OperationFailure.verification("The result has no audio track.") }
        let actual = try await reopened.load(.duration).seconds
        guard actual.isFinite, abs(actual-(end-start)) <= 0.15 else { throw OperationFailure.verification("Audio duration changed unexpectedly.") }
        if let target = options.targetBytes, Int64(try output.resourceValues(forKeys:[.fileSizeKey]).fileSize ?? 0) > target { throw OperationFailure.invalidOptions("The chosen audio bitrate cannot meet this size limit. Choose a lower bitrate or a larger limit.") }
    }
}

// AVFoundation supports cancelling an asynchronous export from another executor.
// Keep the session reference immutable while bridging its callback API.
private final class MediaExportHandle: @unchecked Sendable {
    let session: AVAssetExportSession
    init(_ session: AVAssetExportSession) { self.session = session }
}
