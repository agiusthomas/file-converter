import Foundation

public enum CommandRunner {
    public static func run(_ executable: URL, arguments: [String], in directory: URL, timeout: TimeInterval = 600) async throws -> Data {
        let process = Process(); process.executableURL = executable; process.arguments = arguments; process.currentDirectoryURL = directory
        process.environment = ["PATH":"/usr/bin:/bin", "TMPDIR":directory.path, "LANG":"en_US.UTF-8"]
        let log = directory.appendingPathComponent(".log-\(UUID().uuidString)")
        FileManager.default.createFile(atPath:log.path,contents:nil)
        let sink = try FileHandle(forWritingTo:log); defer { try? sink.close(); try? FileManager.default.removeItem(at:log) }
        process.standardInput = FileHandle.nullDevice; process.standardOutput = sink; process.standardError = sink
        try process.run(); let started = Date()
        do {
            while process.isRunning {
                try Task.checkCancellation()
                guard Date().timeIntervalSince(started) < timeout, (try log.resourceValues(forKeys:[.fileSizeKey]).fileSize ?? 0) < 8 * 1024 * 1024 else { throw OperationFailure.resourceLimit }
                try await Task.sleep(nanoseconds:50_000_000)
            }
            let data = try Data(contentsOf:log)
            guard process.terminationStatus == 0 else { throw OperationFailure.process("Engine failed: " + String(decoding:data.suffix(3000),as:UTF8.self)) }
            return data
        } catch {
            if process.isRunning { process.terminate(); try? await Task.sleep(nanoseconds:100_000_000); if process.isRunning { kill(process.processIdentifier,SIGKILL) }; process.waitUntilExit() }
            throw error
        }
    }
}
public struct ExternalEngine: Sendable {
    public var packs: [InstalledEnginePack]
    public init(packs: [InstalledEnginePack]) { self.packs = packs }
    public func tool(_ name: String, pack: String) throws -> URL {
        guard let item = packs.first(where: { $0.id == pack }), let relative = item.manifest.tools[name] else { throw OperationFailure.missingEngine("Install the \(pack.capitalized) pack to use this operation.") }
        return item.location.appendingPathComponent(relative)
    }
    public func mediaBuild(in directory: URL) async throws -> MediaBuildCapabilities {
        let binary = try tool("ffmpeg",pack:"media")
        let encoders = try await CommandRunner.run(binary,arguments:["-hide_banner","-loglevel","error","-encoders"],in:directory)
        let muxers = try await CommandRunner.run(binary,arguments:["-hide_banner","-loglevel","error","-muxers"],in:directory)
        return MediaBuildCapabilities.parse(encoders:String(decoding:encoders,as:UTF8.self),muxers:String(decoding:muxers,as:UTF8.self))
    }
    public func inspectMedia(_ input: URL) async throws -> AssetDescriptor {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("media-probe-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:false)
        defer { try? FileManager.default.removeItem(at:directory) }
        let data = try await CommandRunner.run(tool("ffprobe",pack:"media"),arguments:["-v","error","-protocol_whitelist","file,pipe","-show_entries","format=format_name,duration,size:stream=index,codec_type,codec_name,width,height","-of","json",input.path],in:directory)
        guard let json = try JSONSerialization.jsonObject(with:data) as? [String:Any], let streams = json["streams"] as? [[String:Any]], let format = json["format"] as? [String:Any], let name = format["format_name"] as? String, streams.contains(where: { ["audio","video"].contains($0["codec_type"] as? String ?? "") }) else { throw OperationFailure.invalidInput("The media engine did not find usable audio or video tracks.") }
        let video = streams.first(where: { $0["codec_type"] as? String == "video" })
        var asset = AssetDescriptor(source:input,family:video == nil ? .audio : .video,format:name.components(separatedBy:",")[0],byteCount:Int64((try input.resourceValues(forKeys:[.fileSizeKey]).fileSize) ?? 0))
        if let value = format["duration"] as? String, let duration = Double(value), duration.isFinite, duration > 0 { asset.duration = duration }
        asset.nativeDecodable = false
        asset.width = video?["width"] as? Int; asset.height = video?["height"] as? Int
        asset.tracks = streams.map { $0["codec_type"] as? String == "audio" ? "soun" : $0["codec_type"] as? String == "video" ? "vide" : "text" }
        return asset
    }
    private func streams(_ input: URL, in directory: URL) async throws -> [[String:Any]] {
        let data = try await CommandRunner.run(tool("ffprobe",pack:"media"),arguments:["-v","error","-protocol_whitelist","file,pipe","-show_streams","-of","json",input.path],in:directory)
        guard let value = try JSONSerialization.jsonObject(with:data) as? [String:Any], let streams = value["streams"] as? [[String:Any]] else { throw OperationFailure.verification("Cannot inspect exported media tracks.") }
        return streams
    }
    public func media(_ request: OperationRequest, to output: URL, in directory: URL) async throws -> [String] {
        let ffmpeg = try tool("ffmpeg",pack:"media"); let profile = request.profiles[0]; let options = request.options
        guard request.inputs.count == 1 else { throw OperationFailure.unsupported("Use the native matching-media join action for multiple files.") }
        var arguments = ["-nostdin","-hide_banner","-loglevel","error","-n","-protocol_whitelist","file,pipe"]
        if options.startTime > 0 { arguments += ["-ss",String(options.startTime)] }
        if let end = options.endTime { arguments += ["-t",String(end-options.startTime)] }
        arguments += ["-i",request.inputs[0].path]
        var filters: [String] = []
        if let crop = options.crop { filters.append("crop=\(crop.width):\(crop.height):\(crop.x):\(crop.y)") }
        switch ((options.rotation % 360) + 360) % 360 { case 90: filters.append("transpose=1"); case 180: filters += ["hflip","vflip"]; case 270: filters.append("transpose=2"); default: break }
        if let size = options.maximumDimension { filters.append("scale=\(size):\(size):force_original_aspect_ratio=decrease:force_divisible_by=2") }
        if options.speed != 1 { filters.append("setpts=PTS/\(options.speed)") }
        if options.streamCopy {
            guard filters.isEmpty, !options.normalizeLoudness, options.targetBytes == nil else { throw OperationFailure.invalidOptions("Stream copy cannot apply filters or target a new size.") }
            let sourceTracks = try await streams(request.inputs[0],in:directory)
            let video = sourceTracks.first { $0["codec_type"] as? String == "video" }, audio = sourceTracks.first { $0["codec_type"] as? String == "audio" }
            let expectedAudio = ["libopus":"opus","libmp3lame":"mp3"][profile.audioCodec ?? ""] ?? profile.audioCodec
            if let expected = profile.videoCodec { guard video?["codec_name"] as? String == expected || (expected == "libvpx-vp9" && video?["codec_name"] as? String == "vp9") else { throw OperationFailure.unsupported("The source video codec does not match this profile. Turn off stream copy to re-encode it.") } }
            if !options.mute, let expectedAudio, audio != nil { guard audio?["codec_name"] as? String == expectedAudio else { throw OperationFailure.unsupported("The source audio codec does not match this profile. Turn off stream copy to re-encode it.") } }
            if profile.videoCodec != nil { arguments += ["-map","0:v:0"] } else { arguments.append("-vn") }
            if options.mute { arguments.append("-an") } else { arguments += ["-map",profile.videoCodec == nil ? "0:a:0" : "0:a:0?"] }
            arguments += ["-c","copy","-sn","-dn"]
        } else {
            if profile.videoCodec != nil || profile.id == "gif" {
                arguments += ["-map","0:v:0"]
                if let codec = profile.videoCodec { arguments += ["-c:v",codec == "h264" ? "h264_videotoolbox" : codec == "hevc" ? "hevc_videotoolbox" : codec] }
                if !filters.isEmpty { arguments += ["-vf",filters.joined(separator:",")] }
            } else { arguments.append("-vn") }
            if options.mute || profile.id == "gif" { arguments.append("-an") }
            else {
                let rate = profile.audioCodec == "libopus" && ![8000,12000,16000,24000,48000].contains(options.sampleRate) ? 48000 : options.sampleRate
                arguments += ["-map",profile.videoCodec == nil ? "0:a:0" : "0:a:0?", "-c:a",profile.audioCodec ?? "aac","-ar",String(rate),"-ac",String(options.channels)]
                if !["wav","aiff","flac"].contains(profile.id) { arguments += ["-b:a",String(options.bitrate)] }
                var audioFilters: [String] = []
                var speed = options.speed
                while speed < 0.5 { audioFilters.append("atempo=0.5"); speed /= 0.5 }
                while speed > 2 { audioFilters.append("atempo=2"); speed /= 2 }
                if speed != 1 { audioFilters.append("atempo=\(speed)") }
                if options.normalizeLoudness { audioFilters.append("loudnorm=I=-16:TP=-1.5:LRA=11") }
                if !audioFilters.isEmpty { arguments += ["-af",audioFilters.joined(separator:",")] }
            }
            arguments += ["-sn","-dn"]
        }
        if let target = options.targetBytes {
            let input = try await inspectMedia(request.inputs[0])
            guard let duration = input.duration else { throw OperationFailure.invalidInput("Cannot determine duration for size targeting.") }
            let time = ((options.endTime ?? duration) - options.startTime) / options.speed
            let bits = Double(target) * 8 * 0.94 / time
            guard bits.isFinite, bits > Double(options.bitrate + 64000), profile.videoCodec != nil else { throw OperationFailure.invalidOptions("This size is too small for the chosen audio bitrate and video duration.") }
            arguments += ["-b:v",String(Int(bits) - options.bitrate)]
        }
        if !options.preserveMetadata || options.removeLocation { arguments += ["-map_metadata","-1"] }
        arguments.append(output.path)
        _ = try await CommandRunner.run(ffmpeg,arguments:arguments,in:directory,timeout:21600)
        if let target = options.targetBytes, Int64(try output.resourceValues(forKeys:[.fileSizeKey]).fileSize ?? 0) > target { throw OperationFailure.invalidOptions("The requested file-size limit could not be reached with these settings.") }
        let source = try await inspectMedia(request.inputs[0]), result = try await inspectMedia(output)
        if let duration = source.duration, let actual = result.duration {
            let expected = (min(options.endTime ?? duration,duration)-options.startTime)/options.speed
            guard expected > 0, abs(actual-expected) <= max(options.streamCopy ? 2 : 0.3,expected*0.01) else { throw OperationFailure.verification("Media duration changed unexpectedly.") }
        }
        if let dimension = options.maximumDimension, let width = result.width, let height = result.height { guard max(width,height) <= dimension else { throw OperationFailure.verification("Media exceeded the chosen dimensions.") } }
        return ["The primary video/audio tracks were exported. Additional tracks, subtitles and attachments are omitted. HDR, color, and alpha may change when re-encoding."] + (options.normalizeLoudness ? ["Loudness normalization uses a single analysis pass."] : []) + (options.streamCopy ? ["Compatible primary streams were copied. Trim boundaries may move to keyframes."] : [])
    }
    public func frame(_ input: URL, time: Double, to output: URL, in directory: URL) async throws {
        let source = try await inspectMedia(input)
        guard source.duration.map({time >= 0 && time < $0}) == true else { throw OperationFailure.invalidOptions("Frame time lies outside the video.") }
        _ = try await CommandRunner.run(tool("ffmpeg",pack:"media"),arguments:["-nostdin","-v","error","-n","-protocol_whitelist","file,pipe","-ss",String(time),"-i",input.path,"-map","0:v:0","-frames:v","1",output.path],in:directory)
    }
    public func document(_ request: OperationRequest, to output: URL, in directory: URL) async throws -> (URL,[String]) {
        let profile = request.profiles[0]; var input = request.inputs[0]
        let source = try await AssetInspector.inspect(input)
        var notices: [String] = []
        if ["md","markdown","html","htm"].contains(source.format), profile.id == "pdf" {
            let text: String
            if ["html","htm"].contains(source.format) { text = try TextEngine.read(input) }
            else {
                let intermediate = directory.appendingPathComponent("markdown.html")
                _ = try await CommandRunner.run(tool("pandoc",pack:"documents"),arguments:["--sandbox","--from","gfm","--to","html","--standalone","--output",intermediate.path,input.path],in:directory)
                text = try TextEngine.read(intermediate)
            }
            input = directory.appendingPathComponent("render.html")
            try Data(HTMLSanitizer.staticDocument(text).utf8).write(to:input)
            notices.append("HTML/Markdown rendering uses static layout: scripts, styles, embedded objects, attributes, and external images are omitted.")
        }
        if ["md","markdown","html","htm"].contains(source.format), profile.id != "pdf" {
            let pandoc = try tool("pandoc",pack:"documents")
            _ = try await CommandRunner.run(pandoc,arguments:["--sandbox","--from",source.format == "markdown" ? "markdown" : source.format == "htm" ? "html" : source.format,"--to",profile.id,"--standalone","--output",output.path,input.path],in:directory)
            return (output,["Document structure is converted; exact page layout and complex tables may change."])
        }
        // A unique profile prevents an existing LibreOffice GUI session from receiving the file.
        let soffice = try tool("soffice",pack:"documents")
        let user = directory.appendingPathComponent("office-profile",isDirectory:true)
        let registry = user.appendingPathComponent("user",isDirectory:true)
        try FileManager.default.createDirectory(at:registry,withIntermediateDirectories:true)
        try Data(#"<?xml version="1.0" encoding="UTF-8"?><oor:items xmlns:oor="http://openoffice.org/2001/registry"><item oor:path="/org.openoffice.Office.Common/Security/Scripting"><prop oor:name="MacroSecurityLevel" oor:op="fuse"><value>3</value></prop><prop oor:name="DisableMacrosExecution" oor:op="fuse"><value>true</value></prop></item><item oor:path="/org.openoffice.Office.Calc/Content/Update"><prop oor:name="Link" oor:op="fuse"><value>0</value></prop></item></oor:items>"#.utf8).write(to:registry.appendingPathComponent("registrymodifications.xcu"))
        let folder = directory.appendingPathComponent("office-output",isDirectory:true)
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        var filter = profile.fileExtension
        if ["csv","tsv"].contains(profile.id) {
            // LibreOffice exports every sheet separately with token 12 = -1.
            let delimiter = profile.id == "tsv" ? 9 : Int(request.options.delimiter.unicodeScalars.first!.value)
            let sheet = request.options.sheet.flatMap(Int.init) ?? -1
            guard request.options.sheet == nil || (1...10000).contains(sheet) else { throw OperationFailure.invalidOptions("Choose a one-based sheet number, or leave empty for every sheet.") }
            filter = "\(profile.id):Text - txt - csv (StarCalc):\(delimiter),34,76,1,,0,false,true,true,false,false,\(sheet)"
        }
        let conversionLog = try await CommandRunner.run(soffice,arguments:["-env:UserInstallation=\(user.absoluteString)","--headless","--nologo","--nodefault","--nolockcheck","--norestore","--convert-to",filter,"--outdir",folder.path,input.path],in:directory,timeout:600)
        let files = try FileManager.default.contentsOfDirectory(at:folder,includingPropertiesForKeys:nil)
        guard !files.isEmpty else { throw OperationFailure.verification("The document engine produced no output. " + String(decoding:conversionLog.suffix(2000),as:UTF8.self)) }
        if ["csv","tsv"].contains(profile.id) {
            let target = output.deletingPathExtension().appendingPathExtension("sheets")
            try FileManager.default.createDirectory(at:target,withIntermediateDirectories:false)
            for file in files {
                let rows = try TextEngine.table(TextEngine.read(file),delimiter:profile.id == "tsv" ? "\t" : Character(request.options.delimiter))
                let destination = target.appendingPathComponent(file.lastPathComponent)
                try TextEngine.write(TextEngine.delimited(rows,delimiter:profile.id == "tsv" ? "\t" : request.options.delimiter),to:destination,options:request.options)
            }
            return (target,["Each selected sheet is exported separately. Displayed values are used; formulas, formatting and workbook features are not preserved."])
        }
        guard files.count == 1, let result = files.first else { throw OperationFailure.verification("The document engine produced an unexpected output set.") }
        try FileManager.default.moveItem(at:result,to:output)
        return (output,notices + ["Fonts, pagination and unsupported Office features may change. Macros and external-link updates are disabled."])
    }
    public func ebook(_ request: OperationRequest, to output: URL, in directory: URL) async throws -> [String] {
        _ = try await CommandRunner.run(tool("ebook-convert",pack:"ebooks"),arguments:[request.inputs[0].path,output.path],in:directory)
        return ["Ebook layout may change. DRM-protected files are unsupported."]
    }
    public func transcribe(_ request: OperationRequest, to output: URL, in directory: URL) async throws -> [String] {
        let item = packs.first { $0.id == "transcription" }
        guard let item, let relative = request.options.model ?? item.manifest.models?.sorted(by:{$0.key < $1.key}).first?.value, item.manifest.files[relative] != nil, item.manifest.models?.values.contains(relative) == true else { throw OperationFailure.missingEngine("Install a verified transcription model first.") }
        let wav = directory.appendingPathComponent("speech.wav")
        var options = OperationOptions(); options.channels = 1; options.sampleRate = 16000
        _ = try await MediaEngine.export(request.inputs,to:wav,profile:ActionCatalog.wav,options:options)
        let base = output.deletingPathExtension()
        let flag = request.profiles[0].id == "srt" ? "-osrt" : request.profiles[0].id == "vtt" ? "-ovtt" : "-otxt"
        _ = try await CommandRunner.run(tool("whisper-cli",pack:"transcription"),arguments:["-m",item.location.appendingPathComponent(relative).path,"-f",wav.path,"-l",request.options.language,flag,"-of",base.path],in:directory,timeout:21600)
        return ["Automatic transcription may contain errors. Review the text and timings before sharing."]
    }
}
