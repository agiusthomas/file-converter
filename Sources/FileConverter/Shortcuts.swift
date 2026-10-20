import AppIntents
import Foundation
import ConverterCore

enum ShortcutFormat: String, AppEnum {
    case jpg, png, pdf, mp4, m4a, wav, zip, txt, vtt
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name:"Output format")
    static var caseDisplayRepresentations: [ShortcutFormat:DisplayRepresentation] = [.jpg:"JPG",.png:"PNG",.pdf:"PDF",.mp4:"MP4 · compatible video",.m4a:"M4A · audio",.wav:"WAV",.zip:"ZIP archive",.txt:"Plain text",.vtt:"WebVTT subtitles"]
}
struct ConvertFilesIntent: AppIntent {
    static var title: LocalizedStringResource = "Convert Files Locally"
    static var description = IntentDescription("Convert files on your Mac and return verified results. Originals remain intact.")
    @Parameter(title:"Files") var files: [IntentFile]
    @Parameter(title:"Output") var format: ShortcutFormat
    static var parameterSummary: some ParameterSummary { Summary("Convert \(\.$files) to \(\.$format)") }
    func perform() async throws -> some IntentResult & ReturnsValue<[IntentFile]> {
        guard !files.isEmpty, files.count <= 1000 else { throw OperationFailure.invalidInput("Choose files to convert.") }
        try TransientWorkspace.removeExpired()
        let temporary = try TransientWorkspace.url(prefix:"shortcut")
        try FileManager.default.createDirectory(at:temporary,withIntermediateDirectories:false)
        // Keep URL-backed results available for Shortcuts; prune owned workspaces
        // after seven days on later launches. Failed invocations clean up at once.
        var completed = false
        defer { if !completed { try? FileManager.default.removeItem(at:temporary) } }
        var inputs: [URL] = []
        for (index,file) in files.enumerated() {
            let folder = temporary.appendingPathComponent("\(index)",isDirectory:true); try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:false)
            let url = folder.appendingPathComponent(URL(fileURLWithPath:file.filename).lastPathComponent)
            try file.data.write(to:url); inputs.append(url)
        }
        let coordinator = JobCoordinator(transport:XPCWorkerTransport(),packs:EnginePacks.installed())
        let assets = try await coordinator.inspect(inputs)
        let action: ActionID
        switch format {
        case .zip: action = .archiveCreate
        case .pdf: action = assets.allSatisfy({$0.family == .image}) ? .imagesToPDF : assets.allSatisfy({$0.family == .pdf}) ? .pdfMerge : .documentConvert
        case .jpg,.png: action = assets.allSatisfy({$0.family == .pdf}) ? .pdfExport : .imageConvert
        case .mp4,.m4a,.wav: action = .mediaConvert
        case .vtt: action = .subtitleConvert
        case .txt: action = assets.allSatisfy({$0.family == .pdf}) ? .pdfText : assets.allSatisfy({$0.family == .subtitle}) ? .subtitleConvert : .textConvert
        }
        guard let descriptor = ActionCatalog.actions(for:assets,installedPacks:Set(EnginePacks.installed().map(\.id)),installedOnly:true).first(where:{$0.id == action}), let profile = descriptor.profiles.first(where:{$0.fileExtension == format.rawValue}) else { throw OperationFailure.unsupported("The requested conversion is not available for all these files.") }
        let batches = descriptor.cardinality == .aggregate ? [inputs] : inputs.map {[$0]}
        var results: [IntentFile] = []
        for batch in batches {
            let manifest = try await coordinator.run(.init(inputs:batch,action:action,profiles:[profile],destination:temporary))
            for output in manifest.outputs {
                let values = try output.url.resourceValues(forKeys:[.isDirectoryKey])
                if values.isDirectory == true { for member in try FileManager.default.contentsOfDirectory(at:output.url,includingPropertiesForKeys:nil) { results.append(IntentFile(fileURL:member,filename:member.lastPathComponent)) } }
                else { results.append(IntentFile(fileURL:output.url,filename:output.url.lastPathComponent)) }
            }
        }
        completed = true; return .result(value:results)
    }
}
struct FileConverterShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent:ConvertFilesIntent(),phrases:["Convert files with \(.applicationName)"],shortTitle:"Convert Files",systemImageName:"arrow.triangle.2.circlepath")
    }
}
