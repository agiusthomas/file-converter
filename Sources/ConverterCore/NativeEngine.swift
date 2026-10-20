import Foundation
import ImageIO
import PDFKit
import CoreGraphics

public actor NativeEngine: EngineAdapter {
    private let images = ImageConverter()
    private let external: ExternalEngine
    private var mediaBuild: MediaBuildCapabilities?
    public init(packs: [InstalledEnginePack] = []) { self.external = ExternalEngine(packs:packs) }
    public func inspect(_ urls: [URL]) async throws -> [AssetDescriptor] {
        guard !urls.isEmpty, urls.count <= 1000 else { throw OperationFailure.resourceLimit }
        var items: [AssetDescriptor] = []
        for url in urls {
            do {
                let native = try await AssetInspector.inspect(url)
                if native.format == "unavailable-media", external.packs.contains(where:{$0.id == "media"}) { items.append(try await external.inspectMedia(url)) } else { items.append(native) }
            }
            catch {
                try Task.checkCancellation()
                if external.packs.contains(where:{$0.id == "media"}), let media = try? await external.inspectMedia(url) { items.append(media) }
                else {
                    let values = try url.resourceValues(forKeys:[.isRegularFileKey,.isSymbolicLinkKey,.fileSizeKey])
                    guard values.isRegularFile == true, values.isSymbolicLink != true else { throw error }
                    var item = AssetDescriptor(source:url,family:.unknown,format:"unrecognized",byteCount:Int64(values.fileSize ?? 0))
                    item.notices = [error.localizedDescription]; items.append(item)
                }
            }
        }
        if external.packs.contains(where: { $0.id == "media" }), items.contains(where: { [.audio,.video].contains($0.family) }) {
            if mediaBuild == nil { mediaBuild = try await external.mediaBuild(in:FileManager.default.temporaryDirectory) }
            let profiles = ActionCatalog.all(installedPacks:["media"]).first(where:{$0.id == .mediaConvert})?.profiles ?? []
            let supported = profiles.filter { mediaBuild?.supports($0) == true }.map(\.id)
            for index in items.indices where [.audio,.video].contains(items[index].family) { items[index].supportedProfiles = supported }
        }
        try Task.checkCancellation(); return items
    }
    public func capabilities(for assets: [AssetDescriptor]) -> [ActionDescriptor] { ActionCatalog.actions(for:assets,installedPacks:Set(external.packs.map(\.id))) }
    public func validate(_ manifest: OutputManifest) async throws {
        for output in manifest.outputs {
            try Task.checkCancellation()
            let values = try output.url.resourceValues(forKeys:[.isDirectoryKey,.isRegularFileKey,.isSymbolicLinkKey])
            guard output.validated, values.isSymbolicLink != true else { throw OperationFailure.verification("An output failed validation.") }
            if values.isRegularFile == true {
                let actual = try FileDigest.sha256(output.url)
                guard output.sha256 == nil || output.sha256 == actual else { throw OperationFailure.verification("Output integrity check failed.") }
            } else if values.isDirectory != true { throw OperationFailure.verification("Output is not a file or folder.") }
        }
    }
    public func execute(_ request: OperationRequest, in directory: URL) async throws -> OutputManifest {
        let options = try request.options.validated()
        let assets = try await inspect(request.inputs)
        let actions = ActionCatalog.actions(for:assets,installedPacks:Set(external.packs.map(\.id)),installedOnly:true)
        guard let descriptor = actions.first(where: { $0.id == request.action }), !request.profiles.isEmpty, request.profiles.count <= 12,
              request.profiles.allSatisfy({ descriptor.profiles.contains($0) }), Set(request.profiles.map(\.id)).count == request.profiles.count else { throw OperationFailure.unsupported("The selected action or output profile is unavailable for these files.") }
        guard request.profiles.count == 1 || request.action == .imageConvert else { throw OperationFailure.invalidOptions("This action accepts one output profile at a time.") }
        if options.targetBytes != nil && ![.imageConvert,.pdfCompress,.mediaConvert].contains(request.action) { throw OperationFailure.unsupported("This action does not support a target file size.") }
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        let work = directory.appendingPathComponent(".work-\(UUID().uuidString)",isDirectory:true)
        try FileManager.default.createDirectory(at:work,withIntermediateDirectories:false)
        defer { try? FileManager.default.removeItem(at:work) }
        var outputs: [OutputArtifact] = [], notices: [String] = []
        func outputURL(_ source: URL, profile: OutputProfile, suffix: String = "") throws -> URL {
            let stem = try options.outputName ?? NamingPolicy.stem(template:options.filenameTemplate,source:source,profile:profile,index:options.sequence,fallbackSuffix:suffix)
            let name = stem + (profile.fileExtension.isEmpty ? "" : "." + profile.fileExtension)
            return directory.appendingPathComponent(name)
        }
        func artifact(_ url: URL, sources: [URL], format: String) async throws -> OutputArtifact {
            let values = try url.resourceValues(forKeys:[.isDirectoryKey,.fileSizeKey,.isSymbolicLinkKey])
            guard values.isSymbolicLink != true else { throw OperationFailure.verification("An output is a symbolic link.") }
            var item = OutputArtifact(url:url,sources:sources,byteCount:Int64(values.fileSize ?? 0),format:format)
            if values.isDirectory == true {
                item.byteCount = 0
                guard let enumerator = FileManager.default.enumerator(at:url,includingPropertiesForKeys:[.isRegularFileKey,.isSymbolicLinkKey,.fileSizeKey]) else { throw OperationFailure.verification("Cannot inspect extracted files.") }
                while let child = enumerator.nextObject() as? URL {
                    let v = try child.resourceValues(forKeys:[.isSymbolicLinkKey,.fileSizeKey,.isRegularFileKey])
                    guard v.isSymbolicLink != true else { throw OperationFailure.verification("An extracted output is a link.") }
                    if v.isRegularFile == true { item.byteCount += Int64(v.fileSize ?? 0) }
                }
            } else {
                guard item.byteCount > 0 || format == "txt" else { throw OperationFailure.verification("The engine created an empty result.") }
                if item.byteCount > 0 {
                    let asset = try await inspect([url])[0]
                    let expected: FileFamily? = ["pdf":FileFamily.pdf,"png":.image,"jpg":.image,"gif":.image,"webp":.image,"heic":.image,"avif":.image,"tiff":.image,"bmp":.image,"epub":.ebook,"mobi":.ebook,"azw3":.ebook,"docx":.document,"odt":.document,"zip":.archive,"tar":.archive,"tar.gz":.archive,"7z":.archive,"mp4":.video,"webm":.video,"m4a":.audio,"wav":.audio,"aiff":.audio,"flac":.audio,"opus":.audio,"mp3":.audio][format]
                    guard expected == nil || expected == asset.family else { throw OperationFailure.verification("The engine produced the wrong file type.") }
                    item.width = asset.width; item.height = asset.height; item.pageCount = asset.pageCount; item.duration = asset.duration
                }
                item.sha256 = try FileDigest.sha256(url)
            }
            return item
        }
        if request.action == .archiveCreate {
            let target = try outputURL(request.inputs[0],profile:request.profiles[0],suffix:" archive")
            try ArchiveEngine.create(request.inputs,to:target,format:request.profiles[0].id)
            outputs.append(try await artifact(target,sources:request.inputs,format:request.profiles[0].id))
            notices.append("Archive permissions use portable defaults; original extended attributes and resource forks are not copied.")
        } else if request.action == .imagesToPDF {
            let target = try outputURL(request.inputs[0],profile:ActionCatalog.pdf,suffix:" combined")
            guard let consumer = CGDataConsumer(url:target as CFURL), let context = CGContext(consumer:consumer,mediaBox:nil,nil) else { throw ConversionError.encodeFailed }
            var count = 0
            for source in request.inputs {
                var imageOptions = imageOptions(options); imageOptions.preserveMetadata = false
                // TIFF retains all frames while applying the same image geometry as ordinary exports.
                let converted = try await images.convert(.init(source:source,format:.tiff,options:imageOptions,destinationDirectory:work))
                guard let data = CGImageSourceCreateWithURL(converted.output as CFURL,nil) else { throw ConversionError.decodeFailed }
                for index in 0..<CGImageSourceGetCount(data) {
                    try Task.checkCancellation(); count += 1; guard count <= 1000 else { throw OperationFailure.resourceLimit }
                    guard let image = CGImageSourceCreateImageAtIndex(data,index,nil) else { throw ConversionError.decodeFailed }
                    let size = CGSize(width:options.pageWidth ?? Double(image.width) * 72 / options.dpi,height:options.pageHeight ?? Double(image.height) * 72 / options.dpi)
                    var box = CGRect(origin:.zero,size:size)
                    guard size.width > 2 * options.margin, size.height > 2 * options.margin else { throw OperationFailure.invalidOptions("Margins leave no space for the image.") }
                    context.beginPDFPage([kCGPDFContextMediaBox:Data(bytes:&box,count:MemoryLayout<CGRect>.size)] as CFDictionary)
                    context.setFillColor(ImageConverter.backgroundColor(options.background)); context.fill(box)
                    let available = box.insetBy(dx:options.margin,dy:options.margin)
                    let ratio = options.fillPage ? max(available.width / CGFloat(image.width),available.height / CGFloat(image.height)) : min(available.width / CGFloat(image.width),available.height / CGFloat(image.height))
                    context.saveGState(); context.clip(to:available)
                    context.draw(image,in:CGRect(x:available.midX-CGFloat(image.width)*ratio/2,y:available.midY-CGFloat(image.height)*ratio/2,width:CGFloat(image.width)*ratio,height:CGFloat(image.height)*ratio))
                    context.restoreGState(); context.endPDFPage()
                }
                try FileManager.default.removeItem(at:converted.output)
            }
            context.closePDF()
            guard PDFDocument(url:target)?.pageCount == count else { throw ConversionError.verificationFailed }
            outputs.append(try await artifact(target,sources:request.inputs,format:"pdf"))
        } else if request.action == .pdfMerge {
            let joined = PDFDocument()
            for input in request.inputs {
                let pdf = try PDFEngine.open(input,password:options.inputPassword)
                for index in try PDFEngine.indices(pdf,options:options) {
                    guard joined.pageCount < 1000, let page = pdf.page(at:index)?.copy() as? PDFPage else { throw OperationFailure.resourceLimit }
                    joined.insert(page,at:joined.pageCount)
                }
            }
            let target = try outputURL(request.inputs[0],profile:ActionCatalog.pdf,suffix:" merged")
            try PDFEngine.save(joined,to:target); outputs.append(try await artifact(target,sources:request.inputs,format:"pdf"))
        } else if request.action == .mediaJoin {
            let target = try outputURL(request.inputs[0],profile:request.profiles[0],suffix:" joined")
            notices += try await MediaEngine.export(request.inputs,to:target,profile:request.profiles[0],options:options,join:true)
            outputs.append(try await artifact(target,sources:request.inputs,format:request.profiles[0].fileExtension))
        } else {
            for (inputIndex,source) in request.inputs.enumerated() {
                try Task.checkCancellation()
                for profile in request.profiles {
                    let suffix = request.inputs.filter { $0.deletingPathExtension().lastPathComponent == source.deletingPathExtension().lastPathComponent }.count > 1 ? " \(inputIndex+1)" : ""
                    var target = try outputURL(source,profile:profile,suffix:suffix)
                    var child = request; child.inputs = [source]; child.profiles = [profile]
                    switch request.action {
                    case .imageConvert:
                        guard let format = ImageFormat.fromExtension(profile.fileExtension) else { throw ConversionError.unsupportedOutput }
                        let result = try await convertImage(source,format:format,options:options,in:work)
                        try FileManager.default.moveItem(at:result.output,to:target); notices += result.notices
                        if options.removeLocation { notices.append("GPS image properties removed and checked. Other location-bearing text is not covered by this setting.") }
                    case .pdfExport,.pdfOrganize,.pdfSplit,.pdfText,.pdfProtect,.pdfCompress:
                        let pdf = try PDFEngine.open(source,password:options.inputPassword); let indices = try PDFEngine.indices(pdf,options:options)
                        if request.action == .pdfExport || request.action == .pdfSplit {
                            try FileManager.default.createDirectory(at:target.deletingPathExtension(),withIntermediateDirectories:false)
                            let folder = target.deletingPathExtension()
                            for (position,index) in indices.enumerated() {
                                try Task.checkCancellation()
                                let url = folder.appendingPathComponent(String(format:"Page %04d.%@",position+1,profile.fileExtension))
                                guard let page = pdf.page(at:index) else { throw ConversionError.decodeFailed }
                                if request.action == .pdfExport { try PDFEngine.saveImage(PDFEngine.render(page,dpi:options.dpi),to:url,format:profile.id == "jpg" ? .jpeg : .png,quality:options.quality) }
                                else { let document = PDFDocument(); document.insert(page,at:0); try PDFEngine.save(document,to:url) }
                            }
                            outputs.append(try await artifact(folder,sources:[source],format:"folder")); continue
                        } else if request.action == .pdfText {
                            let text = indices.compactMap { pdf.page(at:$0)?.string }.joined(separator:"\n\n")
                            try TextEngine.write(text,to:target,options:options)
                            if text.isEmpty { notices.append("No selectable text was found. Use Recognize scanned text.") }
                        } else if request.action == .pdfCompress {
                            try compressPDF(pdf,indices:indices,to:target,options:options)
                            notices.append("PDF rebuilt from page images: selectable text, links, forms, annotations, and signatures are removed.")
                        } else {
                            let document = PDFDocument()
                            for index in indices { guard let page = pdf.page(at:index)?.copy() as? PDFPage else { throw ConversionError.decodeFailed }; page.rotation = (page.rotation + (options.pageRotations[index+1] ?? options.rotation) % 360) % 360; document.insert(page,at:document.pageCount) }
                            if request.action == .pdfProtect && options.outputPassword == nil { throw OperationFailure.invalidOptions("Enter a new PDF opening password.") }
                            try PDFEngine.save(document,to:target,password:request.action == .pdfProtect ? options.outputPassword : nil)
                        }
                    case .pdfOCR:
                        if assets[inputIndex].family == .pdf {
                            let document = try PDFEngine.open(source,password:options.inputPassword); let indices = try PDFEngine.indices(document,options:options)
                            if profile.id == "txt" {
                                var text = ""
                                for index in indices { try Task.checkCancellation(); guard let page = document.page(at:index) else { throw ConversionError.decodeFailed }; let rendered = try PDFEngine.render(page,dpi:options.dpi); let image = options.scanCleanup ? try ScanProcessor.clean(rendered) : rendered; text += try PDFEngine.recognize(image,language:options.language).compactMap { $0.topCandidates(1).first?.string }.joined(separator:"\n") + "\n\n" }
                                try TextEngine.write(text,to:target,options:options)
                            } else {
                                _ = try PDFEngine.searchable(count:indices.count,page:{ index in
                                    guard let page = document.page(at:indices[index]) else { throw ConversionError.decodeFailed }
                                    let rendered = try PDFEngine.render(page,dpi:options.dpi)
                                    let image = options.scanCleanup ? try ScanProcessor.clean(rendered) : rendered
                                    return (image,try PDFEngine.displayedSize(page))
                                },to:target,language:options.language)
                            }
                        } else {
                            let converted = try await convertImage(source,format:.png,options:options,in:work)
                            guard let data = CGImageSourceCreateWithURL(converted.output as CFURL,nil), let image = CGImageSourceCreateImageAtIndex(data,0,nil) else { throw ConversionError.decodeFailed }
                            if profile.id == "txt" { let text = try PDFEngine.recognize(image,language:options.language).compactMap { $0.topCandidates(1).first?.string }.joined(separator:"\n"); try TextEngine.write(text,to:target,options:options) }
                            else { _ = try PDFEngine.searchable(count:1,page:{ _ in (image,CGSize(width:Double(image.width)*72/options.dpi,height:Double(image.height)*72/options.dpi)) },to:target,language:options.language) }
                        }
                        notices.append("OCR is automatic and can misread text or reading order. Review before sharing.")
                    case .textConvert:
                        let text = try TextEngine.read(source,encoding:options.sourceEncoding)
                        if ["csv","tsv"].contains(profile.id) {
                            let rows = try TextEngine.table(text,delimiter:assets[inputIndex].format == "tsv" ? "\t" : Character(options.delimiter))
                            try TextEngine.write(TextEngine.delimited(rows,delimiter:profile.id == "tsv" ? "\t" : options.delimiter),to:target,options:options)
                        } else if profile.id == "html" {
                            let html = "<!doctype html><html><head><meta charset=\"\(options.encoding)\"></head><body><pre>\(TextEngine.escapedHTML(text))</pre></body></html>"
                            try TextEngine.write(html,to:target,options:options); notices.append("Native HTML export preserves text in a plain, preformatted layout. Rich Markdown conversion needs the Documents pack.")
                        } else { try TextEngine.write(text,to:target,options:options) }
                    case .subtitleConvert:
                        let text = try TextEngine.read(source,encoding:options.sourceEncoding)
                        try TextEngine.write(TextEngine.subtitle(TextEngine.cues(text),format:profile.id,offset:options.subtitleOffset),to:target,options:options)
                    case .archiveExtract:
                        _ = try ArchiveEngine.extract(source,to:target,selected:options.archiveMembers)
                        notices.append("Links, special files and unsafe paths are rejected. Extracted files use portable permissions.")
                    case .mediaConvert,.mediaExtractAudio:
                        if external.packs.contains(where: { $0.id == "media" }) { notices += try await external.media(child,to:target,in:work) }
                        else { notices += try await MediaEngine.export([source],to:target,profile:profile,options:options) }
                    case .mediaFrame:
                        if assets[inputIndex].nativeDecodable == false { try await external.frame(source,time:options.startTime,to:target,in:work) }
                        else { try PDFEngine.saveImage(await MediaEngine.frame(source,time:options.startTime),to:target,format:profile.id == "jpg" ? .jpeg : .png,quality:options.quality) }
                    case .documentConvert: let result = try await external.document(child,to:target,in:work); target = result.0; notices += result.1
                    case .ebookConvert: notices += try await external.ebook(child,to:target,in:work)
                    case .transcribe: notices += try await external.transcribe(child,to:target,in:work)
                    default: throw OperationFailure.unsupported("Unsupported operation.")
                    }
                    outputs.append(try await artifact(target,sources:[source],format:profile.fileExtension))
                }
            }
        }
        guard !outputs.isEmpty else { throw OperationFailure.verification("No outputs were produced.") }
        let required: String?
        switch request.action {
        case .documentConvert: required = "documents"
        case .ebookConvert: required = "ebooks"
        case .transcribe: required = "transcription"
        case .mediaConvert,.mediaExtractAudio: required = external.packs.contains(where:{$0.id == "media"}) ? "media" : nil
        case .mediaFrame: required = assets.contains(where:{$0.nativeDecodable == false}) ? "media" : nil
        default: required = nil
        }
        var manifest = OutputManifest(jobID:request.id,outputs:outputs,notices:Array(NSOrderedSet(array:notices)) as? [String] ?? notices,engine:required ?? "native")
        manifest.engineVersions = ["macOS":ProcessInfo.processInfo.operatingSystemVersionString]
        if request.action == .imageConvert && request.profiles.contains(where:{$0.id == "webp"}) { manifest.engineVersions?["libwebp"] = "1.6.0" }
        if [.archiveCreate,.archiveExtract].contains(request.action) { manifest.engineVersions?["libarchive"] = ArchiveEngine.version }
        if let pack = external.packs.first(where:{$0.id == required}) { manifest.engineVersions?[pack.id+"/pack"] = pack.manifest.version; for (name,version) in pack.manifest.engineVersions { manifest.engineVersions?[pack.id+"/"+name] = version } }
        try await validate(manifest); return manifest
    }
    private func imageOptions(_ options: OperationOptions) -> ConversionOptions {
        var result = ConversionOptions(quality:options.quality,preserveMetadata:options.preserveMetadata)
        result.maximumDimension = options.maximumDimension; result.crop = options.crop; result.rotation = options.rotation; result.background = options.background; result.removeLocation = options.removeLocation; result.scanCleanup = options.scanCleanup
        return result
    }
    private func convertImage(_ source: URL, format: ImageFormat, options: OperationOptions, in directory: URL) async throws -> ConversionResult {
        var settings = imageOptions(options)
        let qualities = format.isLossy ? stride(from:options.quality,through:options.minimumQuality,by:-(max(0.01,options.quality-options.minimumQuality)/5)).map { $0 } : [options.quality]
        var dimension = options.maximumDimension
        for pass in 0..<(options.allowDownscale ? 5 : 1) {
            for quality in qualities {
                try Task.checkCancellation(); settings.quality = quality; settings.maximumDimension = dimension
                let result = try await images.convert(.init(source:source,format:format,options:settings,destinationDirectory:directory))
                if options.targetBytes == nil || result.byteCount <= options.targetBytes! { return result }
                if dimension == nil { dimension = max(result.width,result.height) }
                try FileManager.default.removeItem(at:result.output)
            }
            if pass < 4 { dimension = max(1,Int(Double(dimension ?? 2048)*0.75)) }
        }
        throw OperationFailure.invalidOptions("The requested file-size limit could not be reached. Allow downscaling, lower quality, or increase the limit.")
    }
    private func compressPDF(_ document: PDFDocument, indices: [Int], to output: URL, options: OperationOptions) throws {
        let levels = options.targetBytes == nil ? [options.dpi] : [options.dpi,max(72,options.dpi*0.75),max(36,options.dpi*0.5)]
        for dpi in Array(NSOrderedSet(array:levels)) as? [Double] ?? levels {
            guard let consumer = CGDataConsumer(url:output as CFURL), let context = CGContext(consumer:consumer,mediaBox:nil,nil) else { throw ConversionError.encodeFailed }
            for index in indices {
                try Task.checkCancellation()
                guard let page = document.page(at:index) else { throw ConversionError.decodeFailed }
                let image = try PDFEngine.render(page,dpi:dpi)
                let data = NSMutableData()
                guard let encoder = CGImageDestinationCreateWithData(data,"public.jpeg" as CFString,1,nil) else { throw ConversionError.encodeFailed }
                CGImageDestinationAddImage(encoder,image,[kCGImageDestinationLossyCompressionQuality:options.quality] as CFDictionary)
                guard CGImageDestinationFinalize(encoder), let decoded = CGImageSourceCreateWithData(data,nil), let compressed = CGImageSourceCreateImageAtIndex(decoded,0,nil) else { throw ConversionError.encodeFailed }
                var box = CGRect(origin:.zero,size:try PDFEngine.displayedSize(page))
                context.beginPDFPage([kCGPDFContextMediaBox:Data(bytes:&box,count:MemoryLayout<CGRect>.size)] as CFDictionary); context.draw(compressed,in:box); context.endPDFPage()
            }
            context.closePDF()
            guard PDFDocument(url:output)?.pageCount == indices.count else { throw ConversionError.verificationFailed }
            let byteCount = Int64(try output.resourceValues(forKeys:[.fileSizeKey]).fileSize ?? 0)
            if options.targetBytes == nil || byteCount <= options.targetBytes! { return }
            try FileManager.default.removeItem(at:output)
        }
        throw OperationFailure.invalidOptions("PDF could not fit the requested size within the supported resolution range.")
    }
}
