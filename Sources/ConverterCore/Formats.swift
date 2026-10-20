import Foundation
import ImageIO
import UniformTypeIdentifiers

public enum ImageFormat: String, CaseIterable, Codable, Sendable, Identifiable {
    case jpeg = "jpg", png, webp, heic, tiff, avif, bmp, gif, pdf
    public var id: String { rawValue }
    public var title: String { rawValue.uppercased() }
    public var typeIdentifier: String {
        switch self {
        case .jpeg: return UTType.jpeg.identifier
        case .png: return UTType.png.identifier
        case .webp: return "org.webmproject.webp"
        case .heic: return UTType.heic.identifier
        case .tiff: return UTType.tiff.identifier
        case .avif: return "public.avif"
        case .bmp: return UTType.bmp.identifier
        case .gif: return UTType.gif.identifier
        case .pdf: return UTType.pdf.identifier
        }
    }
    public var isLossy: Bool { [.jpeg, .heic, .webp, .avif].contains(self) }
    public static func fromExtension(_ value: String) -> Self? {
        switch value.lowercased() {
        case "jpeg", "jpe": return .jpeg
        case "tif": return .tiff
        case "heif": return .heic
        default: return Self(rawValue: value.lowercased())
        }
    }
}

public struct CapabilityRegistry: Sendable {
    public let writableFormats: [ImageFormat]
    public init() {
        let identifiers = Set(CGImageDestinationCopyTypeIdentifiers() as! [String])
        writableFormats = [.jpeg, .png, .webp, .heic, .tiff, .avif, .bmp, .pdf].filter {
            $0 == .pdf || $0 == .webp || identifiers.contains($0.typeIdentifier)
        }
    }
    public init(writableFormats: [ImageFormat]) { self.writableFormats = writableFormats }
    public func accepts(_ url: URL) -> Bool {
        guard url.isFileURL, let format = ImageFormat.fromExtension(url.pathExtension) else { return false }
        return format != .pdf
    }
    public func destinations(for urls: [URL]) -> [ImageFormat] {
        guard !urls.isEmpty, urls.allSatisfy(accepts) else { return [] }
        let inputs = Set(urls.compactMap { ImageFormat.fromExtension($0.pathExtension) })
        return writableFormats.filter { !inputs.contains($0) }
    }
}

public struct ConversionOptions: Sendable {
    public var quality: Double
    public var preserveMetadata: Bool
    public var maximumDimension: Int?
    public var crop: CropRect?
    public var rotation: Int = 0
    public var background: String = "FFFFFF"
    public var removeLocation: Bool = false
    public var scanCleanup: Bool = false
    public init(quality: Double = 0.9, preserveMetadata: Bool = true) {
        self.quality = min(1, max(0, quality))
        self.preserveMetadata = preserveMetadata
    }
}

public struct ConversionRequest: Sendable {
    public let source: URL
    public let format: ImageFormat
    public let options: ConversionOptions
    public let destinationDirectory: URL?
    public init(source: URL, format: ImageFormat, options: ConversionOptions = .init(), destinationDirectory: URL? = nil) {
        self.source = source
        self.format = format
        self.options = options
        self.destinationDirectory = destinationDirectory
    }
}

public struct ConversionResult: Sendable {
    public let source: URL
    public let output: URL
    public let width: Int
    public let height: Int
    public let pageCount: Int
    public let byteCount: Int64
    public let notices: [String]
}

public enum ConversionError: LocalizedError {
    case unreadable, unsupportedOutput, tooLarge, multipleFrames, decodeFailed, encodeFailed, verificationFailed, destinationUnavailable
    public var errorDescription: String? {
        switch self {
        case .unreadable: return "This file could not be read as an image."
        case .unsupportedOutput: return "This output format is not available on this Mac."
        case .tooLarge: return "This image exceeds the current limit of 256 MB or 100 million pixels."
        case .multipleFrames: return "This image has multiple frames or pages. Choose TIFF or PDF to keep every frame."
        case .decodeFailed: return "The image could not be decoded. The original is unchanged."
        case .encodeFailed: return "The image encoder could not save this format."
        case .verificationFailed: return "The converted file failed verification. No output was published."
        case .destinationUnavailable: return "The output folder is not writable. Choose an accessible folder."
        }
    }
}
