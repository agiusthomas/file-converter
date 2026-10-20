import Foundation
import CoreImage
import Vision

public enum ScanProcessor {
    /// Rectify a confidently detected page, then improve grayscale readability.
    /// The caller controls the PDF page's physical dimensions independently.
    public static func clean(_ image: CGImage) throws -> CGImage {
        try Task.checkCancellation()
        var source = CIImage(cgImage:image)
        let request = VNDetectRectanglesRequest(); request.maximumObservations = 1; request.minimumConfidence = 0.8; request.minimumSize = 0.6
        try VNImageRequestHandler(cgImage:image).perform([request])
        if let rectangle = request.results?.first, rectangle.boundingBox.width * rectangle.boundingBox.height > 0.5 {
            func vector(_ point: CGPoint) -> CIVector { CIVector(x:point.x * CGFloat(image.width),y:point.y * CGFloat(image.height)) }
            source = source.applyingFilter("CIPerspectiveCorrection",parameters:["inputTopLeft":vector(rectangle.topLeft),"inputTopRight":vector(rectangle.topRight),"inputBottomLeft":vector(rectangle.bottomLeft),"inputBottomRight":vector(rectangle.bottomRight)])
        }
        source = source.applyingFilter("CIColorControls",parameters:[kCIInputSaturationKey:0,kCIInputContrastKey:1.15,kCIInputBrightnessKey:0.02])
        let extent = source.extent.integral
        guard extent.width.isFinite,extent.height.isFinite,extent.width > 0,extent.height > 0,extent.width * extent.height <= 100000000 else { throw OperationFailure.resourceLimit }
        let context = CIContext(options:[.useSoftwareRenderer:true])
        guard let result = context.createCGImage(source,from:extent,format:.RGBA8,colorSpace:CGColorSpace(name:CGColorSpace.sRGB)) else { throw ConversionError.decodeFailed }; return result
    }
}
