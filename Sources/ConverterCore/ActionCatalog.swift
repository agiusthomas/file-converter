import Foundation

public enum ActionCatalog {
    public static let png = OutputProfile("png", "PNG", "png")
    public static let jpg = OutputProfile("jpg", "JPG", "jpg")
    public static let pdf = OutputProfile("pdf", "PDF", "pdf")
    public static let txt = OutputProfile("txt", "Plain text", "txt")
    public static let mp4 = OutputProfile("mp4-h264", "MP4 · H.264 / AAC", "mp4", videoCodec: "h264", audioCodec: "aac")
    public static let hevc = OutputProfile("mp4-hevc", "MP4 · HEVC / AAC", "mp4", videoCodec: "hevc", audioCodec: "aac")
    public static let m4a = OutputProfile("m4a-aac", "M4A · AAC", "m4a", audioCodec: "aac")
    public static let wav = OutputProfile("wav", "WAV · PCM", "wav", audioCodec: "pcm_s16le")
    public static var imageProfiles: [OutputProfile] { CapabilityRegistry().writableFormats.map { OutputProfile($0.rawValue, $0.title, $0.rawValue) } }
    public static func all(installedPacks: Set<String> = []) -> [ActionDescriptor] {
        let media = installedPacks.contains("media"), documents = installedPacks.contains("documents")
        return [
            .init(.imageConvert, "Convert image", families: [.image], cardinality: .multiple, profiles: imageProfiles),
            .init(.imagesToPDF, "Combine into PDF", families: [.image], cardinality: .aggregate, profiles: [pdf]),
            .init(.pdfExport, "Export page images", families: [.pdf], cardinality: .extract, profiles: [png, jpg]),
            .init(.pdfOrganize, "Arrange PDF pages", families: [.pdf], profiles: [pdf]),
            .init(.pdfMerge, "Merge PDFs", families: [.pdf], cardinality: .aggregate, profiles: [pdf]),
            .init(.pdfSplit, "Split into pages", families: [.pdf], cardinality: .extract, profiles: [pdf]),
            .init(.pdfText, "Extract text", families: [.pdf], profiles: [txt]),
            .init(.pdfOCR, "Recognize scanned text", families: [.pdf,.image], profiles: [txt, .init("searchable-pdf", "Searchable PDF", "pdf")]),
            .init(.pdfCompress, "Compress PDF", families: [.pdf], profiles: [pdf], limitation: "Rebuilds page images; removes selectable text, links, forms and annotations. Use searchable PDF afterward when needed."),
            .init(.pdfProtect, "Protect PDF", families: [.pdf], profiles: [pdf]),
            .init(.mediaConvert, "Convert audio / video", families: [.audio,.video], profiles: [mp4, hevc, m4a, wav] + (media ? [.init("aiff", "AIFF · PCM", "aiff", audioCodec: "pcm_s16be"), .init("flac", "FLAC", "flac", audioCodec: "flac"), .init("mp3", "MP3", "mp3", audioCodec: "libmp3lame"), .init("opus", "Opus", "opus", audioCodec: "libopus"), .init("webm", "WebM · VP9 / Opus", "webm", videoCodec: "libvpx-vp9", audioCodec: "libopus"), .init("gif", "Animated GIF", "gif")] : []), limitation: "Exports primary tracks. Additional tracks, subtitles, HDR, color, and alpha may change or be omitted; preview and review before sharing."),
            .init(.mediaExtractAudio, "Extract audio", families: [.video], profiles: [m4a,wav]),
            .init(.mediaFrame, "Export video frame", families: [.video], profiles: [png,jpg]),
            .init(.mediaJoin, "Join matching media", families: [.audio,.video], cardinality: .aggregate, profiles: [mp4,m4a]),
            .init(.textConvert, "Convert text / table", families: [.text], profiles: [txt,.init("html", "HTML", "html"),.init("md", "Markdown", "md"),.init("csv", "CSV", "csv"),.init("tsv", "TSV", "tsv")]),
            .init(.subtitleConvert, "Convert subtitles", families: [.subtitle], profiles: [.init("srt", "SRT", "srt"),.init("vtt", "WebVTT", "vtt"),txt]),
            .init(.documentConvert, "Convert document", families: [.document,.spreadsheet,.presentation,.text], profiles: [pdf,.init("docx", "Word document", "docx"),.init("odt", "OpenDocument text", "odt"),txt,.init("epub", "EPUB", "epub"),.init("csv", "CSV · selected sheets", "csv"),.init("tsv", "TSV · selected sheets", "tsv")], requiredPack: "documents", available: documents),
            .init(.archiveCreate, "Create archive", families: FileFamily.allCases, cardinality: .aggregate, profiles: [.init("zip", "ZIP", "zip"),.init("tar", "TAR", "tar"),.init("tar.gz", "TAR.GZ", "tar.gz"),.init("7z", "7-Zip", "7z")], available: ArchiveEngine.available),
            .init(.archiveExtract, "Extract archive", families: [.archive], cardinality: .extract, profiles: [.init("folder", "Folder", "")], available: ArchiveEngine.available),
            .init(.ebookConvert, "Convert ebook", families: [.ebook,.document,.text], profiles: [.init("epub", "EPUB", "epub"),.init("azw3", "AZW3", "azw3"),.init("mobi", "MOBI", "mobi"),txt], requiredPack: "ebooks", available: installedPacks.contains("ebooks")),
            .init(.transcribe, "Transcribe locally", families: [.audio,.video], profiles: [txt,.init("srt", "SRT", "srt"),.init("vtt", "WebVTT", "vtt")], requiredPack: "transcription", available: installedPacks.contains("transcription"))
        ]
    }
    public static func actions(for assets: [AssetDescriptor], installedPacks: Set<String> = [], installedOnly: Bool = false) -> [ActionDescriptor] {
        guard !assets.isEmpty else { return [] }
        return all(installedPacks: installedPacks).filter { descriptor in
            assets.allSatisfy { descriptor.families.contains($0.family) } && (!installedOnly || descriptor.available) && !(descriptor.id == .archiveExtract && assets.contains { $0.format == "folder" }) && !(descriptor.id == .mediaExtractAudio && assets.contains { !$0.tracks.contains("soun") }) && !(descriptor.id == .mediaJoin && (Set(assets.map(\.family)).count > 1 || assets.contains(where:{$0.nativeDecodable == false})))
        }.map { descriptor in
            var action = descriptor
            if action.id == .mediaConvert && assets.contains(where: { $0.family == .audio }) { action.profiles.removeAll { $0.videoCodec != nil || $0.id == "gif" } }
            if [.mediaConvert,.mediaExtractAudio].contains(action.id) {
                action.profiles = action.profiles.filter { profile in assets.allSatisfy { $0.supportedProfiles?.contains(profile.id) ?? true } }
                if action.id == .mediaConvert && action.profiles.isEmpty && !installedPacks.contains("media") { action.available = false; action.requiredPack = "media"; action.profiles = all(installedPacks:["media"]).first(where:{$0.id == .mediaConvert})?.profiles ?? [] }
            }
            if action.id == .mediaFrame && assets.contains(where:{$0.nativeDecodable == false}) && !installedPacks.contains("media") { action.available = false; action.requiredPack = "media" }
            if action.id == .documentConvert {
                if assets.contains(where: { $0.family == .spreadsheet }) { action.profiles = action.profiles.filter { ["pdf","csv","tsv"].contains($0.id) } }
                else if assets.contains(where: { $0.family == .presentation }) { action.profiles = [pdf] }
                else { action.profiles.removeAll { ["csv","tsv"].contains($0.id) } }
            }
            if action.id == .textConvert && !assets.allSatisfy({ ["csv","tsv"].contains($0.format) }) { action.profiles.removeAll { ["csv","tsv"].contains($0.id) } }
            return action
        }.filter { !$0.profiles.isEmpty && (!installedOnly || $0.available) }
    }
}
