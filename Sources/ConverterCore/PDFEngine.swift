import Foundation
import PDFKit
import ImageIO
import Vision
import CoreText

public enum PDFEngine {
    public static func displayedSize(_ page: PDFPage) throws -> CGSize {
        guard let ref = page.pageRef else { throw ConversionError.decodeFailed }
        let box = ref.getBoxRect(.mediaBox); return abs(ref.rotationAngle) % 180 == 90 ? CGSize(width:box.height,height:box.width) : box.size
    }
    public static func open(_ url: URL, password: String?) throws -> PDFDocument {
        guard let document = PDFDocument(url: url) else { throw OperationFailure.invalidInput("Cannot open this PDF.") }
        if document.isLocked { guard let password, document.unlock(withPassword: password) else { throw OperationFailure.passwordRequired } }
        guard document.pageCount > 0, document.pageCount <= 1000 else { throw OperationFailure.resourceLimit }
        return document
    }
    public static func indices(_ document: PDFDocument, options: OperationOptions) throws -> [Int] {
        let pages = options.pages.isEmpty ? Array(1...document.pageCount) : options.pages
        guard pages.allSatisfy({ $0 > 0 && $0 <= document.pageCount }) else { throw OperationFailure.invalidOptions("A selected page does not exist.") }
        return pages.map { $0 - 1 }
    }
    public static func render(_ page: PDFPage, dpi: Double) throws -> CGImage {
        guard let ref = page.pageRef else { throw OperationFailure.invalidInput("Cannot read this PDF page.") }
        let box = ref.getBoxRect(.mediaBox); let swapped = abs(ref.rotationAngle) % 180 == 90
        let width = (swapped ? box.height : box.width) * dpi / 72
        let height = (swapped ? box.width : box.height) * dpi / 72
        guard width.isFinite, height.isFinite, width > 0, height > 0, width <= 100000, height <= 100000, width * height <= 100000000 else { throw OperationFailure.resourceLimit }
        guard let context = CGContext(data: nil, width: max(1,Int(width.rounded())), height: max(1,Int(height.rounded())), bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw OperationFailure.resourceLimit }
        let rectangle = CGRect(x: 0, y: 0, width: context.width, height: context.height)
        context.setFillColor(CGColor(gray: 1, alpha: 1)); context.fill(rectangle)
        context.concatenate(ref.getDrawingTransform(.mediaBox, rect: rectangle, rotate: 0, preserveAspectRatio: true)); context.drawPDFPage(ref)
        guard let image = context.makeImage() else { throw OperationFailure.verification("PDF page could not render.") }; return image
    }
    public static func saveImage(_ image: CGImage, to url: URL, format: ImageFormat, quality: Double) throws {
        guard let writer = CGImageDestinationCreateWithURL(url as CFURL, format.typeIdentifier as CFString, 1, nil) else { throw ConversionError.encodeFailed }
        CGImageDestinationAddImage(writer, image, [kCGImageDestinationLossyCompressionQuality:quality] as CFDictionary)
        guard CGImageDestinationFinalize(writer), let read = CGImageSourceCreateWithURL(url as CFURL,nil), let decoded = CGImageSourceCreateImageAtIndex(read,0,nil), decoded.width == image.width, decoded.height == image.height else { throw ConversionError.verificationFailed }
    }
    public static func save(_ document: PDFDocument, to url: URL, password: String? = nil) throws {
        var options: [PDFDocumentWriteOption:Any] = [:]
        if let password { guard !password.isEmpty else { throw OperationFailure.invalidOptions("Use a nonempty PDF password.") }; options[.userPasswordOption] = password; options[.ownerPasswordOption] = UUID().uuidString }
        guard document.write(to: url, withOptions: options), let reopened = PDFDocument(url: url) else { throw OperationFailure.verification("PDF could not be saved and reopened.") }
        if let password { guard reopened.isLocked, reopened.unlock(withPassword: password) else { throw OperationFailure.verification("PDF password verification failed.") } }
        guard reopened.pageCount == document.pageCount else { throw OperationFailure.verification("PDF page count changed during export.") }
    }
    public static func recognize(_ image: CGImage, language: String) throws -> [VNRecognizedTextObservation] {
        let request = VNRecognizeTextRequest(); request.recognitionLevel = .accurate; request.usesLanguageCorrection = true
        if language != "auto" {
            guard try request.supportedRecognitionLanguages().contains(language) else { throw OperationFailure.invalidOptions("This OCR language is not supported on this Mac.") }
            request.recognitionLanguages = [language]
        }
        try VNImageRequestHandler(cgImage: image).perform([request])
        return (request.results ?? []).sorted { a,b in abs(a.boundingBox.midY - b.boundingBox.midY) > 0.015 ? a.boundingBox.midY > b.boundingBox.midY : a.boundingBox.minX < b.boundingBox.minX }
    }
    public static func searchable(count: Int, page: (Int) throws -> (CGImage,CGSize), to output: URL, language: String) throws -> String {
        guard let consumer = CGDataConsumer(url: output as CFURL), let context = CGContext(consumer: consumer, mediaBox: nil, nil) else { throw ConversionError.encodeFailed }
        var texts: [String] = []
        for index in 0..<count {
            let (image,size) = try page(index)
            try Task.checkCancellation()
            var bounds = CGRect(origin: .zero, size: size)
            let observations = try recognize(image, language: language)
            let content = observations.compactMap { $0.topCandidates(1).first?.string }
            texts.append(content.joined(separator: "\n"))
            context.beginPDFPage([kCGPDFContextMediaBox:Data(bytes:&bounds,count:MemoryLayout<CGRect>.size)] as CFDictionary)
            context.draw(image, in: bounds)
            for observation in observations {
                guard let text = observation.topCandidates(1).first?.string else { continue }
                let box = observation.boundingBox
                let font = CTFontCreateWithName("Helvetica" as CFString, max(1, box.height * size.height), nil)
                let line = CTLineCreateWithAttributedString(NSAttributedString(string:text,attributes:[NSAttributedString.Key(kCTFontAttributeName as String):font]))
                let measured = CTLineGetTypographicBounds(line,nil,nil,nil)
                context.saveGState(); context.setTextDrawingMode(.invisible)
                context.textMatrix = .identity
                context.translateBy(x:box.minX * size.width,y:box.minY * size.height)
                if measured > 0 { context.scaleBy(x:box.width * size.width / measured,y:1) }
                context.textPosition = .zero; CTLineDraw(line,context); context.restoreGState()
            }
            context.endPDFPage()
        }
        context.closePDF()
        guard let document = PDFDocument(url:output), document.pageCount == count else { throw OperationFailure.verification("Searchable PDF failed validation.") }
        if texts.contains(where: { !$0.isEmpty }), (document.string ?? "").trimmingCharacters(in:.whitespacesAndNewlines).isEmpty { throw OperationFailure.verification("The searchable text layer is missing.") }
        return texts.joined(separator:"\n\n")
    }
}
