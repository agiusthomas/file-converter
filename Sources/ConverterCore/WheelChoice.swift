import Foundation

public struct WheelChoice: Identifiable, Sendable {
    public var id: String { action.rawValue + ":" + profile.id }
    public var title: String
    public var action: ActionID
    public var profile: OutputProfile
    public var aggregate = false
    public var needsOptions = false
    public static func common(_ assets: [AssetDescriptor], installedPacks: Set<String> = []) -> [Self] {
        let actions = ActionCatalog.actions(for:assets,installedPacks:installedPacks,installedOnly:true)
        if assets.allSatisfy({$0.family == .image}) {
            let inputFormats = Set(assets.map(\.format))
            let profiles = ActionCatalog.imageProfiles.filter { $0.id != "pdf" && !inputFormats.contains($0.fileExtension) && (!assets.contains(where: { ($0.pageCount ?? 1) > 1 }) || $0.id == "tiff") }
            return Array(profiles.map { Self(title:$0.title,action:.imageConvert,profile:$0) }.prefix(7)) + [Self(title:"PDF",action:.imagesToPDF,profile:ActionCatalog.pdf,aggregate:true)]
        }
        let labels: [ActionID:String] = [.pdfExport:"IMAGES",.pdfText:"TEXT",.pdfSplit:"SPLIT",.pdfMerge:"MERGE",.pdfOrganize:"PAGES",.pdfOCR:"OCR",.pdfProtect:"PROTECT",.pdfCompress:"SMALLER",.mediaConvert:"CONVERT",.mediaExtractAudio:"AUDIO",.mediaFrame:"FRAME",.mediaJoin:"JOIN",.archiveCreate:"ZIP",.archiveExtract:"EXTRACT",.textConvert:"TEXT",.subtitleConvert:"SUBTITLE",.documentConvert:"PDF",.ebookConvert:"EPUB",.transcribe:"TRANSCRIBE"]
        return Array(actions.filter { action in !(action.id == .pdfMerge && assets.count < 2) }.compactMap { action in
            guard let profile = action.profiles.first else { return nil }
            return Self(title:labels[action.id] ?? action.title,action:action.id,profile:profile,aggregate:action.cardinality == .aggregate,needsOptions:[.pdfOrganize,.pdfProtect,.pdfCompress,.mediaConvert,.mediaJoin,.transcribe].contains(action.id))
        }.prefix(8))
    }
}
