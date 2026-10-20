import Foundation

public enum FileFamily: String, Codable, CaseIterable, Sendable { case image, pdf, audio, video, document, spreadsheet, presentation, text, subtitle, archive, ebook, unknown }
public struct AssetDescriptor: Codable, Sendable, Identifiable {
    public var id: URL { source }
    public let source: URL
    public var family: FileFamily
    public var format: String
    public var byteCount: Int64
    public var width: Int?
    public var height: Int?
    public var pageCount: Int?
    public var duration: Double?
    public var tracks: [String] = []
    public var notices: [String] = []
    public var members: [String] = []
    public var supportedProfiles: [String]?
    public var metadata: [String:String]?
    public var nativeDecodable: Bool?
    public init(source: URL, family: FileFamily, format: String, byteCount: Int64) {
        self.source = source; self.family = family; self.format = format; self.byteCount = byteCount
    }
}
public enum ActionID: String, Codable, CaseIterable, Sendable {
    case imageConvert = "image.convert", imagesToPDF = "image.combine-pdf"
    case pdfExport = "pdf.export", pdfOrganize = "pdf.organize", pdfMerge = "pdf.merge", pdfSplit = "pdf.split", pdfText = "pdf.text", pdfOCR = "pdf.ocr", pdfCompress = "pdf.compress", pdfProtect = "pdf.protect"
    case mediaConvert = "media.convert", mediaExtractAudio = "media.extract-audio", mediaFrame = "media.frame", mediaJoin = "media.join"
    case textConvert = "text.convert", subtitleConvert = "subtitle.convert"
    case documentConvert = "document.convert", archiveCreate = "archive.create", archiveExtract = "archive.extract", ebookConvert = "ebook.convert", transcribe
}
public enum Cardinality: String, Codable, Sendable { case perFile, aggregate, extract, multiple }
public struct OutputProfile: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var title: String
    public var fileExtension: String
    public var videoCodec: String?
    public var audioCodec: String?
    public init(_ id: String, _ title: String, _ fileExtension: String, videoCodec: String? = nil, audioCodec: String? = nil) {
        self.id = id; self.title = title; self.fileExtension = fileExtension; self.videoCodec = videoCodec; self.audioCodec = audioCodec
    }
}
public struct ActionDescriptor: Codable, Sendable, Identifiable {
    public var id: ActionID
    public var title: String
    public var families: [FileFamily]
    public var cardinality: Cardinality
    public var profiles: [OutputProfile]
    public var requiredPack: String?
    public var available: Bool
    public var limitation: String?
    public init(_ id: ActionID, _ title: String, families: [FileFamily], cardinality: Cardinality = .perFile, profiles: [OutputProfile], requiredPack: String? = nil, available: Bool = true, limitation: String? = nil) {
        self.id = id; self.title = title; self.families = families; self.cardinality = cardinality; self.profiles = profiles; self.requiredPack = requiredPack; self.available = available; self.limitation = limitation
    }
}
public struct CropRect: Codable, Sendable, Equatable {
    public var x: Int; public var y: Int; public var width: Int; public var height: Int
    public init(x: Int, y: Int, width: Int, height: Int) { self.x = x; self.y = y; self.width = width; self.height = height }
}
public struct OperationOptions: Codable, Sendable {
    public var quality = 0.9
    public var preserveMetadata = true
    public var removeLocation = false
    public var scanCleanup = false
    public var maximumDimension: Int?
    public var crop: CropRect?
    public var rotation = 0
    public var background = "FFFFFF"
    public var targetBytes: Int64?
    public var minimumQuality = 0.3
    public var allowDownscale = false
    public var pages: [Int] = [] // One-based, ordered; duplicates intentionally repeat a page.
    public var pageRotations: [Int:Int] = [:]
    public var dpi = 144.0
    public var pageWidth: Double?
    public var pageHeight: Double?
    public var margin = 0.0
    public var fillPage = false
    public var inputPassword: String?
    public var outputPassword: String?
    public var startTime = 0.0
    public var endTime: Double?
    public var speed = 1.0
    public var mute = false
    public var sampleRate = 44100
    public var channels = 2
    public var bitrate = 192000
    public var normalizeLoudness = false
    public var streamCopy = false
    public var subtitleOffset = 0.0
    public var encoding = "utf-8"
    public var sourceEncoding = "auto"
    public var lineEndings = "lf"
    public var delimiter = ","
    public var sheet: String?
    public var archiveMembers: [String] = []
    public var language = "auto"
    public var model: String?
    public var outputName: String?
    public var filenameTemplate: String?
    public var sequence = 1
    private enum CodingKeys: String, CodingKey { case quality, preserveMetadata, removeLocation, scanCleanup, maximumDimension, crop, rotation, background, targetBytes, minimumQuality, allowDownscale, pages, pageRotations, dpi, pageWidth, pageHeight, margin, fillPage, inputPassword, outputPassword, startTime, endTime, speed, mute, sampleRate, channels, bitrate, normalizeLoudness, streamCopy, subtitleOffset, encoding, sourceEncoding, lineEndings, delimiter, sheet, archiveMembers, language, model, outputName, filenameTemplate, sequence }
    public init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy:CodingKeys.self)
        quality = try c.decodeIfPresent(Double.self,forKey:.quality) ?? quality
        preserveMetadata = try c.decodeIfPresent(Bool.self,forKey:.preserveMetadata) ?? preserveMetadata
        removeLocation = try c.decodeIfPresent(Bool.self,forKey:.removeLocation) ?? removeLocation
        scanCleanup = try c.decodeIfPresent(Bool.self,forKey:.scanCleanup) ?? scanCleanup
        if c.contains(.maximumDimension) { maximumDimension = try c.decodeIfPresent(Int.self,forKey:.maximumDimension) }
        if c.contains(.crop) { crop = try c.decodeIfPresent(CropRect.self,forKey:.crop) }
        rotation = try c.decodeIfPresent(Int.self,forKey:.rotation) ?? rotation
        background = try c.decodeIfPresent(String.self,forKey:.background) ?? background
        if c.contains(.targetBytes) { targetBytes = try c.decodeIfPresent(Int64.self,forKey:.targetBytes) }
        minimumQuality = try c.decodeIfPresent(Double.self,forKey:.minimumQuality) ?? minimumQuality
        allowDownscale = try c.decodeIfPresent(Bool.self,forKey:.allowDownscale) ?? allowDownscale
        pages = try c.decodeIfPresent([Int].self,forKey:.pages) ?? pages
        pageRotations = try c.decodeIfPresent([Int:Int].self,forKey:.pageRotations) ?? pageRotations
        dpi = try c.decodeIfPresent(Double.self,forKey:.dpi) ?? dpi
        if c.contains(.pageWidth) { pageWidth = try c.decodeIfPresent(Double.self,forKey:.pageWidth) }
        if c.contains(.pageHeight) { pageHeight = try c.decodeIfPresent(Double.self,forKey:.pageHeight) }
        margin = try c.decodeIfPresent(Double.self,forKey:.margin) ?? margin
        fillPage = try c.decodeIfPresent(Bool.self,forKey:.fillPage) ?? fillPage
        if c.contains(.inputPassword) { inputPassword = try c.decodeIfPresent(String.self,forKey:.inputPassword) }
        if c.contains(.outputPassword) { outputPassword = try c.decodeIfPresent(String.self,forKey:.outputPassword) }
        startTime = try c.decodeIfPresent(Double.self,forKey:.startTime) ?? startTime
        if c.contains(.endTime) { endTime = try c.decodeIfPresent(Double.self,forKey:.endTime) }
        speed = try c.decodeIfPresent(Double.self,forKey:.speed) ?? speed
        mute = try c.decodeIfPresent(Bool.self,forKey:.mute) ?? mute
        sampleRate = try c.decodeIfPresent(Int.self,forKey:.sampleRate) ?? sampleRate
        channels = try c.decodeIfPresent(Int.self,forKey:.channels) ?? channels
        bitrate = try c.decodeIfPresent(Int.self,forKey:.bitrate) ?? bitrate
        normalizeLoudness = try c.decodeIfPresent(Bool.self,forKey:.normalizeLoudness) ?? normalizeLoudness
        streamCopy = try c.decodeIfPresent(Bool.self,forKey:.streamCopy) ?? streamCopy
        subtitleOffset = try c.decodeIfPresent(Double.self,forKey:.subtitleOffset) ?? subtitleOffset
        encoding = try c.decodeIfPresent(String.self,forKey:.encoding) ?? encoding
        sourceEncoding = try c.decodeIfPresent(String.self,forKey:.sourceEncoding) ?? sourceEncoding
        lineEndings = try c.decodeIfPresent(String.self,forKey:.lineEndings) ?? lineEndings
        delimiter = try c.decodeIfPresent(String.self,forKey:.delimiter) ?? delimiter
        if c.contains(.sheet) { sheet = try c.decodeIfPresent(String.self,forKey:.sheet) }
        archiveMembers = try c.decodeIfPresent([String].self,forKey:.archiveMembers) ?? archiveMembers
        language = try c.decodeIfPresent(String.self,forKey:.language) ?? language
        if c.contains(.model) { model = try c.decodeIfPresent(String.self,forKey:.model) }
        if c.contains(.outputName) { outputName = try c.decodeIfPresent(String.self,forKey:.outputName) }
        filenameTemplate = try c.decodeIfPresent(String.self,forKey:.filenameTemplate)
        sequence = try c.decodeIfPresent(Int.self,forKey:.sequence) ?? 1
    }
    public init() {}
    public func validated() throws -> Self {
        guard quality.isFinite, (0...1).contains(quality), minimumQuality.isFinite, (0...quality).contains(minimumQuality),
              dpi.isFinite, (36...600).contains(dpi), margin.isFinite, margin >= 0,
              startTime.isFinite, startTime >= 0, speed.isFinite, (0.25...4).contains(speed),
              subtitleOffset.isFinite, rotation % 90 == 0,
              (maximumDimension.map { (1...100000).contains($0) } ?? true),
              (targetBytes.map { $0 > 0 } ?? true),
              (endTime.map { $0.isFinite && $0 > startTime } ?? true),
              (pageWidth.map { $0.isFinite && $0 > 2 * margin && $0 <= 14400 } ?? true),
              (pageHeight.map { $0.isFinite && $0 > 2 * margin && $0 <= 14400 } ?? true),
              (pageWidth == nil) == (pageHeight == nil),
              [8000,16000,22050,24000,32000,44100,48000,96000].contains(sampleRate), [1,2].contains(channels),
              (8000...1000000).contains(bitrate), ["lf", "crlf"].contains(lineEndings),
              ["utf-8", "utf-16", "windows-1252", "ascii"].contains(encoding), ["auto","utf-8","utf-16","windows-1252","ascii"].contains(sourceEncoding),
              delimiter.count == 1, background.range(of: "^[0-9a-fA-F]{6}$", options: .regularExpression) != nil,
              pages.allSatisfy({ $0 > 0 }), pages.count <= 1000, pageRotations.count <= 1000, pageRotations.allSatisfy({ $0.key > 0 && $0.value % 90 == 0 }) else { throw OperationFailure.invalidOptions("One or more options are outside supported limits.") }
        if let crop { guard (0...100000).contains(crop.x), (0...100000).contains(crop.y), crop.width > 0, crop.height > 0, crop.width <= 100000, crop.height <= 100000 else { throw OperationFailure.invalidOptions("Invalid crop rectangle.") } }
        if let outputName { guard !outputName.isEmpty, outputName.utf8.count <= 200, !outputName.contains("\\"), !outputName.unicodeScalars.contains(where:{CharacterSet.controlCharacters.contains($0)}), !outputName.contains("/"), !outputName.contains(":"), outputName != ".", outputName != ".." else { throw OperationFailure.invalidOptions("Use a filename without path separators.") } }
        guard sequence > 0, sequence <= 1000000 else { throw OperationFailure.invalidOptions("Invalid output sequence number.") }
        if let filenameTemplate { _ = try NamingPolicy.stem(template:filenameTemplate,source:URL(fileURLWithPath:"/sample.png"),profile:ActionCatalog.png,index:sequence) }
        return self
    }
}
public struct OperationRequest: Codable, Sendable, Identifiable {
    public var id: UUID
    public var inputs: [URL]
    public var action: ActionID
    public var profiles: [OutputProfile]
    public var options: OperationOptions
    public var destination: URL?
    public var relativeSourceRoot: URL?
    public init(id: UUID = UUID(), inputs: [URL], action: ActionID, profiles: [OutputProfile], options: OperationOptions = .init(), destination: URL? = nil) {
        self.id = id; self.inputs = inputs; self.action = action; self.profiles = profiles; self.options = options; self.destination = destination
    }
    public var redacted: Self { var copy = self; copy.options.inputPassword = nil; copy.options.outputPassword = nil; return copy }
}
public struct OutputArtifact: Codable, Sendable, Identifiable {
    public var id: URL { url }
    public var url: URL
    public var sources: [URL]
    public var byteCount: Int64
    public var format: String
    public var width: Int?
    public var height: Int?
    public var pageCount: Int?
    public var duration: Double?
    public var sha256: String?
    public var recipeStep: Int?
    public var validated = true
    public init(url: URL, sources: [URL], byteCount: Int64, format: String) { self.url = url; self.sources = sources; self.byteCount = byteCount; self.format = format }
}
public struct OutputManifest: Codable, Sendable {
    public var schemaVersion = 1
    public var jobID: UUID
    public var outputs: [OutputArtifact]
    public var notices: [String]
    public var engine: String
    public var engineVersions: [String:String]?
    public init(jobID: UUID, outputs: [OutputArtifact], notices: [String] = [], engine: String = "native") { self.jobID = jobID; self.outputs = outputs; self.notices = notices; self.engine = engine }
}
public enum JobState: String, Codable, Sendable { case queued, analysing, running, validating, publishing, succeeded, failed, cancelled, interrupted }
public struct JobRecord: Codable, Identifiable, Sendable {
    public var id: UUID { request.id }
    public var request: OperationRequest
    public var state: JobState
    public var createdAt: Date
    public var manifest: OutputManifest?
    public var error: String?
    public var ownerPID: Int32?
    public var stageDirectory: URL?
    public var recipe: Recipe?
    public var completedRecipeExports: [Int]?
    public var pinnedEngines: [String:String]?
    public init(request: OperationRequest, state: JobState = .queued) { self.request = request.redacted; self.state = state; self.createdAt = Date(); self.ownerPID = ProcessInfo.processInfo.processIdentifier }
}
public struct RecipeStep: Codable, Sendable {
    public var action: ActionID
    public var profiles: [OutputProfile]
    public var options: OperationOptions
    public var export = false
    public init(action: ActionID, profiles: [OutputProfile], options: OperationOptions = .init(), export: Bool = false) { self.action = action; self.profiles = profiles; self.options = options; self.export = export }
}
public struct Recipe: Codable, Identifiable, Sendable {
    public var schemaVersion = 1
    public var id: UUID
    public var name: String
    public var steps: [RecipeStep]
    public init(id: UUID = UUID(), name: String, steps: [RecipeStep]) { self.id = id; self.name = name; self.steps = steps }
    public var redacted: Self { var copy = self; for index in copy.steps.indices { copy.steps[index].options.inputPassword = nil; copy.steps[index].options.outputPassword = nil }; return copy }
    public func validate() throws {
        guard schemaVersion == 1, !name.trimmingCharacters(in: .whitespaces).isEmpty, !steps.isEmpty, steps.count <= 20, steps.last?.export == true else { throw OperationFailure.invalidOptions("Recipes need a name, at most 20 steps, and a final export.") }
        for step in steps {
            _ = try step.options.validated(); guard !step.profiles.isEmpty else { throw OperationFailure.invalidOptions("Every recipe step needs an output profile.") }
            if !step.export && step.action == .imageConvert && !step.profiles.allSatisfy({["png","tiff","bmp"].contains($0.id)}) { throw OperationFailure.invalidOptions("Use PNG, TIFF, or BMP between image recipe steps to avoid repeated lossy encoding.") }
            if !step.export && step.action == .mediaConvert && !step.profiles.allSatisfy({["wav","flac","aiff"].contains($0.id)}) { throw OperationFailure.invalidOptions("Export compressed media only at terminal recipe steps; use lossless audio intermediates.") }
        }
    }
}
public enum OperationFailure: LocalizedError {
    case unsupported(String), invalidOptions(String), invalidInput(String), verification(String), missingEngine(String), cancelled, resourceLimit, passwordRequired, process(String)
    public var errorDescription: String? {
        switch self {
        case .unsupported(let s), .invalidOptions(let s), .invalidInput(let s), .verification(let s), .missingEngine(let s), .process(let s): return s
        case .cancelled: return "Cancelled. Originals are unchanged."
        case .resourceLimit: return "The operation exceeds the supported size, page, or expansion limit."
        case .passwordRequired: return "This PDF needs its opening password."
        }
    }
}
public protocol EngineAdapter: Sendable {
    func inspect(_ urls: [URL]) async throws -> [AssetDescriptor]
    func capabilities(for assets: [AssetDescriptor]) async -> [ActionDescriptor]
    func execute(_ request: OperationRequest, in directory: URL) async throws -> OutputManifest
    func validate(_ manifest: OutputManifest) async throws
}
