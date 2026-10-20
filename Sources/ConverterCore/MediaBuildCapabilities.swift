import Foundation

/// Query the installed binary, so an optional build cannot advertise codecs that
/// its license or build configuration omitted.
public struct MediaBuildCapabilities: Sendable {
    public var encoders: Set<String>
    public var muxers: Set<String>
    public init(encoders: Set<String>, muxers: Set<String>) { self.encoders = encoders; self.muxers = muxers }
    public static func parse(encoders: String, muxers: String) -> Self {
        func names(_ text: String, encoder: Bool) -> Set<String> {
            Set(text.split(separator:"\n").compactMap { line in
                let fields = line.split(whereSeparator: { $0.isWhitespace })
                guard fields.count > 1, fields[1] != "=" else { return nil }
                if encoder { guard fields[0].count == 6, ["A","V","S"].contains(String(fields[0].prefix(1))) else { return nil } }
                else { guard fields[0].contains("E"), fields[0].allSatisfy({ "DE.d".contains($0) }) else { return nil } }
                return String(fields[1])
            })
        }
        return Self(encoders:names(encoders,encoder:true),muxers:names(muxers,encoder:false))
    }
    public func supports(_ profile: OutputProfile) -> Bool {
        let muxer = ["m4a-aac":"ipod", "mp4-h264":"mp4", "mp4-hevc":"mp4", "opus":"opus"][profile.id] ?? profile.fileExtension
        guard muxers.contains(muxer) else { return false }
        let video = profile.videoCodec.map { $0 == "h264" ? "h264_videotoolbox" : $0 == "hevc" ? "hevc_videotoolbox" : $0 } ?? (profile.id == "gif" ? "gif" : nil)
        return (video.map(encoders.contains) ?? true) && (profile.audioCodec.map(encoders.contains) ?? true)
    }
}
