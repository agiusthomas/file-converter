import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import WebPBridge

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
        if request.format == .webp {
            let image = try transformed(normalizedImage(source,index:0),options:request.options)
            try writeWebP(image,to:stage,quality:request.options.quality)
            firstDimensions = (image.width,image.height)
            guard let verified = CGImageSourceCreateWithURL(stage as CFURL,nil), let decoded = CGImageSourceCreateImageAtIndex(verified,0,nil), decoded.width == image.width, decoded.height == image.height else { throw ConversionError.verificationFailed }
            notices.append("WebP exports use sRGB and omit source metadata. Transparency is preserved; animation is not supported.")
        } else if request.format == .pdf {
            guard let consumer = CGDataConsumer(url: stage as CFURL), let context = CGContext(consumer: consumer, mediaBox: nil, nil) else { throw ConversionError.encodeFailed }
            for index in 0..<count {
                try Task.checkCancellation()
                let image = try transformed(normalizedImage(source, index: index), options: request.options)
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
                var image = try transformed(normalizedImage(source, index: index), options: request.options)
                if [.jpeg, .bmp].contains(request.format), image.alphaInfo != .none {
                    image = try flattened(image, background: request.options.background)
                    let notice = request.options.background == "FFFFFF" ? "Transparency is flattened onto white." : "Transparency is flattened onto #\(request.options.background)."
                    if !notices.contains(notice) { notices.append(notice) }
                }
                if index == 0 { firstDimensions = (image.width, image.height) }
                expectedDimensions.append((image.width, image.height))
                var properties = request.options.preserveMetadata ? (CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any] ?? [:]) : [:]
                if request.options.removeLocation { properties.removeValue(forKey: kCGImagePropertyGPSDictionary) }
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
                if request.options.removeLocation,
                   let props = CGImageSourceCopyPropertiesAtIndex(verified, index, nil) as? [CFString: Any],
                   props[kCGImagePropertyGPSDictionary] != nil { throw ConversionError.verificationFailed }
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
    private func flattened(_ image: CGImage, background: String = "FFFFFF") throws -> CGImage {
        let colorSpace = image.colorSpace?.model == .rgb ? image.colorSpace! : CGColorSpace(name: CGColorSpace.sRGB)!
        guard let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { throw ConversionError.decodeFailed }
        let bounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        context.setFillColor(Self.backgroundColor(background)); context.fill(bounds)
        context.draw(image, in: bounds)
        guard let result = context.makeImage() else { throw ConversionError.decodeFailed }
        return result
    }
    public static func backgroundColor(_ hex: String) -> CGColor {
        let value = UInt32(hex, radix: 16) ?? 0xffffff
        return CGColor(red: CGFloat((value >> 16) & 255) / 255, green: CGFloat((value >> 8) & 255) / 255, blue: CGFloat(value & 255) / 255, alpha: 1)
    }
    private func writeWebP(_ image: CGImage, to output: URL, quality: Double) throws {
        guard image.width <= 16383, image.height <= 16383 else { throw OperationFailure.resourceLimit }
        let stride = image.width * 4
        var rgba = [UInt8](repeating:0,count:stride * image.height)
        try rgba.withUnsafeMutableBytes { bytes in
            guard let context = CGContext(data:bytes.baseAddress,width:image.width,height:image.height,bitsPerComponent:8,bytesPerRow:stride,space:CGColorSpace(name:CGColorSpace.sRGB)!,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else { throw ConversionError.encodeFailed }
            context.draw(image,in:CGRect(x:0,y:0,width:image.width,height:image.height))
        }
        // CoreGraphics renders premultiplied pixels; libwebp takes straight RGBA.
        for index in Swift.stride(from:0,to:rgba.count,by:4) {
            let alpha = Int(rgba[index+3])
            if alpha > 0 && alpha < 255 { for channel in 0..<3 { rgba[index+channel] = UInt8(min(255,(Int(rgba[index+channel])*255+alpha/2)/alpha)) } }
        }
        var encoded: UnsafeMutablePointer<UInt8>?
        let size = fc_webp_encode(rgba,Int32(image.width),Int32(image.height),Int32(stride),Float(quality*100),&encoded)
        guard size > 0, let encoded else { throw ConversionError.encodeFailed }
        defer { fc_webp_free(encoded) }
        try Data(bytes:encoded,count:size).write(to:output)
    }
    private func transformed(_ original: CGImage, options: ConversionOptions) throws -> CGImage {
        var image = options.scanCleanup ? try ScanProcessor.clean(original) : original
        if let crop = options.crop {
            guard crop.x >= 0, crop.y >= 0, crop.width > 0, crop.height > 0,
                  crop.x < image.width, crop.y < image.height,
                  crop.width <= image.width - crop.x, crop.height <= image.height - crop.y,
                  let cropped = image.cropping(to: CGRect(x: crop.x, y: crop.y, width: crop.width, height: crop.height)) else { throw OperationFailure.invalidOptions("Crop lies outside the image.") }
            image = cropped
        }
        let rotation = ((options.rotation % 360) + 360) % 360
        let swapped = rotation == 90 || rotation == 270
        let rawWidth = swapped ? image.height : image.width, rawHeight = swapped ? image.width : image.height
        let scale = min(1, Double(options.maximumDimension ?? max(rawWidth,rawHeight)) / Double(max(rawWidth,rawHeight)))
        if scale == 1 && rotation == 0 { return image }
        let width = max(1, Int(Double(rawWidth) * scale)), height = max(1, Int(Double(rawHeight) * scale))
        let color = image.colorSpace?.model == .rgb ? image.colorSpace! : CGColorSpace(name: CGColorSpace.sRGB)!
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: color, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw ConversionError.decodeFailed }
        context.interpolationQuality = .high
        context.translateBy(x: CGFloat(width)/2, y: CGFloat(height)/2)
        context.rotate(by: -CGFloat(rotation) * .pi / 180)
        context.scaleBy(x: scale, y: scale)
        context.draw(image, in: CGRect(x: -CGFloat(image.width)/2, y: -CGFloat(image.height)/2, width: CGFloat(image.width), height: CGFloat(image.height)))
        guard let result = context.makeImage() else { throw ConversionError.decodeFailed }; return result
    }
}
