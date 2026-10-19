import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

public actor ImageConverter {
    public init() {}

    public func convert(_ request: ConversionRequest) throws -> ConversionResult {
        try Task.checkCancellation()
        let sourceAccess = request.source.startAccessingSecurityScopedResource()
        defer { if sourceAccess { request.source.stopAccessingSecurityScopedResource() } }
        let directory = request.destinationDirectory ?? request.source.deletingLastPathComponent()
        let directoryAccess = directory.startAccessingSecurityScopedResource()
        defer { if directoryAccess { directory.stopAccessingSecurityScopedResource() } }
        let registry = CapabilityRegistry()
        guard registry.writableFormats.contains(request.format) else { throw ConversionError.unsupportedOutput }
        let fileValues = try request.source.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard fileValues.isRegularFile == true else { throw ConversionError.unreadable }
        guard (fileValues.fileSize ?? 0) <= 256 * 1_024 * 1_024 else { throw ConversionError.tooLarge }
        guard let source = CGImageSourceCreateWithURL(request.source as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary) else { throw ConversionError.unreadable }
        let count = CGImageSourceGetCount(source)
        guard count > 0, count <= 1_000 else { throw ConversionError.tooLarge }
        guard count == 1 || [.tiff, .pdf].contains(request.format) else { throw ConversionError.multipleFrames }
        // Bound the entire decoded job, not just each individual frame.
        var totalPixels: Int64 = 0
        for index in 0..<count {
            let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any] ?? [:]
            let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.int64Value ?? 0
            let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.int64Value ?? 0
            guard width > 0, height > 0, width <= 100_000, height <= 100_000 else { throw ConversionError.tooLarge }
            totalPixels += width * height
            guard totalPixels <= 100_000_000 else { throw ConversionError.tooLarge }
        }
        let stageDirectory = directory.appendingPathComponent(".file-converter-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: stageDirectory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: stageDirectory) }
        let stage = stageDirectory.appendingPathComponent("output.\(request.format.rawValue)")
        var firstDimensions = (width: 0, height: 0)
        var expectedDimensions: [(width: Int, height: Int)] = []
        var notices: [String] = []
        if count > 1, CGImageSourceGetType(source) as String? != UTType.tiff.identifier {
            notices.append("Every frame is kept as a still page. Animation timing is not preserved.")
        }
        if request.format == .pdf {
            guard let consumer = CGDataConsumer(url: stage as CFURL), let context = CGContext(consumer: consumer, mediaBox: nil, nil) else { throw ConversionError.encodeFailed }
            for index in 0..<count {
                try Task.checkCancellation()
                let image = try normalizedImage(source, index: index)
                if index == 0 { firstDimensions = (image.width, image.height) }
                expectedDimensions.append((image.width, image.height))
                // 144 DPI keeps the page size practical while retaining the full image data.
                var box = CGRect(x: 0, y: 0, width: Double(image.width) / 2, height: Double(image.height) / 2)
                let data = Data(bytes: &box, count: MemoryLayout<CGRect>.size)
                context.beginPDFPage([kCGPDFContextMediaBox: data] as CFDictionary)
                context.setFillColor(CGColor(gray: 1, alpha: 1)); context.fill(box)
                context.draw(image, in: box); context.endPDFPage()
            }
            context.closePDF()
            guard let pdf = CGPDFDocument(stage as CFURL), pdf.numberOfPages == count else { throw ConversionError.verificationFailed }
            notices.append("PDF pages retain the image pixels; image metadata is not copied.")
        } else {
            guard let destination = CGImageDestinationCreateWithURL(stage as CFURL, request.format.typeIdentifier as CFString, count, nil) else { throw ConversionError.encodeFailed }
            for index in 0..<count {
                try Task.checkCancellation()
                var image = try normalizedImage(source, index: index)
                if [.jpeg, .bmp].contains(request.format), image.alphaInfo != .none {
                    image = try flattened(image)
                    if !notices.contains("Transparency is flattened onto white.") { notices.append("Transparency is flattened onto white.") }
                }
                if index == 0 { firstDimensions = (image.width, image.height) }
                expectedDimensions.append((image.width, image.height))
                var properties = request.options.preserveMetadata ? (CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any] ?? [:]) : [:]
                // Pixel transforms must not leave a second orientation transform in the output.
                properties[kCGImagePropertyOrientation] = 1
                properties[kCGImagePropertyPixelWidth] = image.width
                properties[kCGImagePropertyPixelHeight] = image.height
                if var tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any] {
                    tiff[kCGImagePropertyTIFFOrientation] = 1; properties[kCGImagePropertyTIFFDictionary] = tiff
                }
                if var exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any] {
                    exif[kCGImagePropertyExifPixelXDimension] = image.width
                    exif[kCGImagePropertyExifPixelYDimension] = image.height
                    properties[kCGImagePropertyExifDictionary] = exif
                }
                properties[kCGImageDestinationLossyCompressionQuality] = request.options.quality
                CGImageDestinationAddImage(destination, image, properties as CFDictionary)
            }
            guard CGImageDestinationFinalize(destination) else { throw ConversionError.encodeFailed }
            guard let verified = CGImageSourceCreateWithURL(stage as CFURL, nil),
                  CGImageSourceGetType(verified) as String? == request.format.typeIdentifier,
                  CGImageSourceGetCount(verified) == count else { throw ConversionError.verificationFailed }
            for index in 0..<count {
                try Task.checkCancellation()
                guard let decoded = CGImageSourceCreateImageAtIndex(verified, index, nil),
                      decoded.width == expectedDimensions[index].width,
                      decoded.height == expectedDimensions[index].height else { throw ConversionError.verificationFailed }
            }
        }
        try Task.checkCancellation()
        let bytes = try stage.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard bytes > 0 else { throw ConversionError.verificationFailed }
        let output = try AtomicPublisher.publish(stagedFile: stage, source: request.source, directory: directory, extension: request.format.rawValue)
        return ConversionResult(source: request.source, output: output, width: firstDimensions.width, height: firstDimensions.height, pageCount: count, byteCount: Int64(bytes), notices: notices)
    }

    private func normalizedImage(_ source: CGImageSource, index: Int) throws -> CGImage {
        let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any] ?? [:]
        let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue ?? 0
        let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue ?? 0
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(width, height),
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, index, options as CFDictionary) else { throw ConversionError.decodeFailed }
        return image
    }
    private func flattened(_ image: CGImage) throws -> CGImage {
        let colorSpace = image.colorSpace?.model == .rgb ? image.colorSpace! : CGColorSpace(name: CGColorSpace.sRGB)!
        guard let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { throw ConversionError.decodeFailed }
        let bounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        context.setFillColor(CGColor(gray: 1, alpha: 1)); context.fill(bounds)
        context.draw(image, in: bounds)
        guard let result = context.makeImage() else { throw ConversionError.decodeFailed }
        return result
    }
}
