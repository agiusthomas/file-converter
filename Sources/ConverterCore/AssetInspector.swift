import Foundation
import ImageIO
import UniformTypeIdentifiers
import PDFKit
import AVFoundation

public enum AssetInspector {
    public static func inspect(_ url: URL) async throws -> AssetDescriptor {
        try Task.checkCancellation()
        let granted = url.startAccessingSecurityScopedResource(); defer { if granted { url.stopAccessingSecurityScopedResource() } }
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isSymbolicLink != true else { throw OperationFailure.unsupported("Choose the original file rather than a symbolic link.") }
        if values.isDirectory == true { return AssetDescriptor(source: url, family: .archive, format: "folder", byteCount: 0) }
        guard values.isRegularFile == true else { throw OperationFailure.invalidInput("Choose a regular file.") }
        let bytes = Int64(values.fileSize ?? 0)
        let handle = try FileHandle(forReadingFrom: url); defer { try? handle.close() }
        let prefix = try handle.read(upToCount: 65536) ?? Data()
        guard !prefix.isEmpty else { throw OperationFailure.invalidInput("The file is empty.") }
        if prefix.starts(with: Data("%PDF-".utf8)) {
            guard bytes <= 2 * 1024 * 1024 * 1024, let pdf = PDFDocument(url: url) else { throw OperationFailure.invalidInput("Cannot read PDF.") }
            var item = AssetDescriptor(source: url, family: .pdf, format: "pdf", byteCount: bytes)
            if pdf.isLocked { item.notices.append("Opening password required.") } else { item.pageCount = pdf.pageCount }
            item.metadata = [:]
            for (attribute,key) in [(PDFDocumentAttribute.titleAttribute,"title"),(.authorAttribute,"author"),(.creatorAttribute,"creator")] { if let value = pdf.documentAttributes?[attribute] as? String { item.metadata?[key] = String(value.prefix(512)) } }
            item.notices.append("Page edits rebuild the PDF; signatures and interactive features may change.")
            return item
        }
        if let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary), let identifier = CGImageSourceGetType(source) as String?, identifier != UTType.pdf.identifier {
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]
            var item = AssetDescriptor(source: url, family: .image, format: UTType(identifier)?.preferredFilenameExtension ?? identifier, byteCount: bytes)
            item.width = properties[kCGImagePropertyPixelWidth] as? Int; item.height = properties[kCGImagePropertyPixelHeight] as? Int
            item.pageCount = CGImageSourceGetCount(source)
            item.metadata = [:]
            for (property,key) in [(kCGImagePropertyProfileName,"colorProfile"),(kCGImagePropertyDepth,"bitDepth"),(kCGImagePropertyOrientation,"orientation"),(kCGImagePropertyHasAlpha,"hasAlpha")] { if let value = properties[property] { item.metadata?[key] = String(describing:value) } }
            item.metadata?["hasGPS"] = properties[kCGImagePropertyGPSDictionary] == nil ? "false" : "true"
            if (properties[kCGImagePropertyHasAlpha] as? Bool) == true { item.notices.append("Has an alpha channel. JPG/BMP flatten it onto the chosen background.") }
            if let depth = properties[kCGImagePropertyDepth] as? Int, depth > 8 { item.notices.append("High bit depth may be reduced during conversion. HDR preservation is not guaranteed.") }
            if (item.pageCount ?? 0) > 1 { item.notices.append("Multiple frames or pages; destinations must preserve them explicitly.") }
            return item
        }
        // Only try media probing for recognizable container headers; never infer support from the extension.
        let media = prefix.starts(with: Data("RIFF".utf8)) || prefix.starts(with: Data("FORM".utf8)) || prefix.starts(with: Data("fLaC".utf8)) || prefix.starts(with: Data("OggS".utf8)) || prefix.starts(with: Data("ID3".utf8)) || prefix.starts(with: [0x1a,0x45,0xdf,0xa3]) || (prefix.count >= 8 && prefix.subdata(in: 4..<8) == Data("ftyp".utf8)) || (prefix.count > 1 && prefix[0] == 0xff && prefix[1] & 0xe0 == 0xe0)
        if media {
            let asset = AVURLAsset(url: url)
            if let tracks = try? await asset.load(.tracks), !tracks.isEmpty {
                let video = tracks.contains { $0.mediaType == .video }
                let detected: String
                if prefix.starts(with:Data("RIFF".utf8)) { detected = prefix.count >= 12 && prefix.subdata(in:8..<12) == Data("WAVE".utf8) ? "wav" : "avi" }
                else if prefix.starts(with:Data("FORM".utf8)) { detected = "aiff" }
                else if prefix.starts(with:Data("fLaC".utf8)) { detected = "flac" }
                else if prefix.starts(with:Data("OggS".utf8)) { detected = prefix.range(of:Data("OpusHead".utf8)) == nil ? "ogg" : "opus" }
                else if prefix.starts(with:[0x1a,0x45,0xdf,0xa3]) { detected = prefix.range(of:Data("webm".utf8)) == nil ? "mkv" : "webm" }
                else if prefix.count >= 12 && prefix.subdata(in:4..<8) == Data("ftyp".utf8) { let brand = String(decoding:prefix.subdata(in:8..<12),as:UTF8.self); detected = brand == "qt  " ? "mov" : brand.hasPrefix("M4A") ? "m4a" : "mp4" }
                else { detected = "mp3" }
                var item = AssetDescriptor(source: url, family: video ? .video : .audio, format: detected, byteCount: bytes)
                let duration = try await asset.load(.duration).seconds
                item.duration = duration.isFinite ? duration : nil
                item.tracks = tracks.map { $0.mediaType.rawValue }
                item.supportedProfiles = []; item.nativeDecodable = true
                if tracks.filter({$0.mediaType == .audio}).count == 1 { item.supportedProfiles?.append("wav") }
                for (id,preset,type) in [("m4a-aac",AVAssetExportPresetAppleM4A,AVFileType.m4a),("mp4-h264",AVAssetExportPresetHighestQuality,AVFileType.mp4),("mp4-hevc",AVAssetExportPresetHEVCHighestQuality,AVFileType.mp4)] {
                    if (id == "m4a-aac" && tracks.contains(where:{$0.mediaType == .audio})) || (id != "m4a-aac" && video), let session = AVAssetExportSession(asset:asset,presetName:preset), session.supportedFileTypes.contains(type) { item.supportedProfiles?.append(id) }
                }
                if let track = tracks.first(where: { $0.mediaType == .video }), let size = try? await track.load(.naturalSize) { item.width = Int(size.width); item.height = Int(size.height) }
                return item
            }
        }
        if media {
            let isAudio = prefix.starts(with:Data("FORM".utf8)) || prefix.starts(with:Data("fLaC".utf8)) || prefix.starts(with:Data("ID3".utf8)) || prefix.starts(with:Data("OggS".utf8)) || (prefix.count >= 12 && prefix.subdata(in:8..<12) == Data("WAVE".utf8)) || (prefix.count > 1 && prefix[0] == 0xff)
            var item = AssetDescriptor(source:url,family:isAudio ? .audio : .video,format:"unavailable-media",byteCount:bytes)
            item.supportedProfiles = []; item.nativeDecodable = false; item.notices = ["A media container was detected, but native decoding is unavailable. Install the Media pack to inspect its tracks and codecs."]
            return item
        }
        let archiveMagic = prefix.starts(with: [0x50,0x4b]) || prefix.starts(with: [0x37,0x7a,0xbc,0xaf,0x27,0x1c]) || prefix.starts(with: Data("Rar!".utf8)) || prefix.starts(with: [0x1f,0x8b]) || (prefix.count > 262 && String(data: prefix.subdata(in: 257..<262), encoding: .ascii) == "ustar")
        if archiveMagic, ArchiveEngine.available {
            let members = try ArchiveEngine.list(url); let names = Set(members.map(\.name))
            var family: FileFamily = .archive; var format = prefix.starts(with: [0x50,0x4b]) ? "zip" : prefix.starts(with: [0x37,0x7a]) ? "7z" : prefix.starts(with: Data("Rar!".utf8)) ? "rar" : prefix.starts(with: [0x1f,0x8b]) ? "tar.gz" : "tar"
            if names.contains("word/document.xml") { family = .document; format = "docx" }
            else if names.contains("xl/workbook.xml") { family = .spreadsheet; format = "xlsx" }
            else if names.contains("ppt/presentation.xml") { family = .presentation; format = "pptx" }
            else if names.contains("mimetype"), let data = try? ArchiveEngine.readMember("mimetype",from:url,limit:256), let mime = String(data:data,encoding:.utf8) {
                switch mime.trimmingCharacters(in:.whitespacesAndNewlines) {
                case "application/epub+zip" where names.contains("META-INF/container.xml"): family = .ebook; format = "epub"
                case "application/vnd.oasis.opendocument.text" where names.contains("content.xml"): family = .document; format = "odt"
                case "application/vnd.oasis.opendocument.spreadsheet" where names.contains("content.xml"): family = .spreadsheet; format = "ods"
                case "application/vnd.oasis.opendocument.presentation" where names.contains("content.xml"): family = .presentation; format = "odp"
                default: break
                }
            }
            if [.document,.spreadsheet,.presentation,.ebook].contains(family) {
                guard bytes <= 512*1024*1024, members.reduce(Int64(0),{$0+$1.size}) <= 2*1024*1024*1024,
                      !members.contains(where:{ ($0.name.hasSuffix(".xml") || $0.name.hasSuffix(".rels")) && $0.size > 32*1024*1024 }) else { throw OperationFailure.resourceLimit }
            }
            var item = AssetDescriptor(source: url, family: family, format: format, byteCount: bytes); item.members = members.map(\.name)
            return item
        }
        if prefix.starts(with: Data("{\\rtf".utf8)) { return AssetDescriptor(source: url, family: .document, format: "rtf", byteCount: bytes) }
        if prefix.count > 68, prefix.subdata(in:60..<68) == Data("BOOKMOBI".utf8) { return AssetDescriptor(source:url,family:.ebook,format:url.pathExtension.lowercased() == "azw3" ? "azw3" : "mobi",byteCount:bytes) }
        // UTF-16 is accepted only when it has a BOM. Arbitrary binary is never treated as text.
        let encoding: String.Encoding = prefix.starts(with: [0xff,0xfe]) || prefix.starts(with: [0xfe,0xff]) ? .utf16 : .utf8
        let knownTextExtension = ["txt","md","markdown","html","htm","csv","tsv","json","srt","vtt"].contains(url.pathExtension.lowercased())
        let sample = String(data: prefix, encoding: encoding) ?? (encoding == .utf8 ? String(data: prefix.dropLast(min(3, prefix.count)), encoding: .utf8) : nil) ?? (knownTextExtension ? String(data:prefix,encoding:.windowsCP1252) : nil)
        guard bytes <= 32 * 1024 * 1024, let sample, !sample.unicodeScalars.contains(where: { $0.value == 0 || ($0.value < 32 && ![9,10,13].contains($0.value)) }) else { throw OperationFailure.unsupported("The file content is not supported by the installed engines.") }
        let ext = url.pathExtension.lowercased()
        let isSubtitle = sample.hasPrefix("WEBVTT") || sample.range(of: #"\d\d:\d\d:\d\d[,\.]\d{3}\s+-->"#, options: .regularExpression) != nil
        return AssetDescriptor(source: url, family: isSubtitle ? .subtitle : .text, format: isSubtitle ? (sample.hasPrefix("WEBVTT") ? "vtt" : "srt") : (["md","markdown","html","htm","csv","tsv","json"].contains(ext) ? ext : "txt"), byteCount: bytes)
    }
}
