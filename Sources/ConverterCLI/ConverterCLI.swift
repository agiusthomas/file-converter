import Foundation
import ConverterCore
import Darwin

@main struct ConverterCLI {
    static func emit<T:Encodable>(_ value:T) throws { let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]; print(String(decoding:try encoder.encode(value),as:UTF8.self)) }
    static func main() async {
        var args = Array(CommandLine.arguments.dropFirst())
        guard !args.isEmpty, !["-h","--help"].contains(args[0]) else { help(); return }
        let command = args.removeFirst()
        let packs = EnginePacks.installed()
        let transport = ProcessWorkerTransport(executable:URL(fileURLWithPath:CommandLine.arguments[0]).standardizedFileURL.deletingLastPathComponent().appendingPathComponent("converter-worker"))
        let coordinator = JobCoordinator(transport:transport,packs:packs)
        do {
            switch command {
            case "capabilities":
                var object = try JSONSerialization.jsonObject(with:JSONEncoder().encode(ActionCatalog.all(installedPacks:Set(packs.map(\.id)))))
                object = ["schemaVersion":1,"imageOutputs":CapabilityRegistry().writableFormats.map(\.rawValue),"actions":object,"archiveEngine":ArchiveEngine.version] as [String:Any]
                print(String(decoding:try JSONSerialization.data(withJSONObject:object,options:[.prettyPrinted,.sortedKeys]),as:UTF8.self))
            case "inspect","actions":
                guard !args.isEmpty else { throw OperationFailure.invalidOptions("Specify files to inspect.") }
                let assets = try await coordinator.inspect(args.map { URL(fileURLWithPath:$0) })
                if command == "inspect" { try emit(Inspection(assets:assets)) } else { try emit(Actions(actions:ActionCatalog.actions(for:assets,installedPacks:Set(packs.map(\.id))))) }
            case "jobs": try emit(Jobs(jobs:await coordinator.records(recoverInterrupted:args.contains("--recover"))))
            case "engines":
                let action = args.first ?? "list"; if !args.isEmpty { args.removeFirst() }
                if action == "list" { try emit(Packs(packs:packs)) }
                else if action == "install", let path = args.first { try emit(EnginePacks.install(URL(fileURLWithPath:path))) }
                else if action == "verify", let path = args.first { try emit(EnginePacks.verify(URL(fileURLWithPath:path),trustedTeam:EnginePacks.signingTeam(EnginePacks.publisherCodeURL))) }
                else if action == "rollback", let id = args.first { try EnginePacks.rollback(id); print("Engine rollback selected. Restart the app to activate it.") }
                else if action == "deactivate", let id = args.first { try EnginePacks.deactivate(id); print("Engine deactivated for future launches; running jobs keep their pinned version.") }
                else { throw OperationFailure.invalidOptions("Use engines list, install PACK.bundle, verify PACK.bundle, rollback ID, or deactivate ID.") }
            case "recipe":
                guard args.count >= 2 else { throw OperationFailure.invalidOptions("Use recipe validate FILE.json or recipe run FILE.json INPUT...") }
                let action = args.removeFirst(), file = URL(fileURLWithPath:args.removeFirst())
                let recipe = try JSONDecoder().decode(Recipe.self,from:Data(contentsOf:file)); try recipe.validate()
                if action == "validate" { try emit(recipe) }
                else if action == "run" { try emit(await coordinator.run(recipe,inputs:args.map { URL(fileURLWithPath:$0) })) }
                else { throw OperationFailure.invalidOptions("Unknown recipe command.") }
            case "run","convert":
                var action: ActionID = .imageConvert, target: String?, destination: URL?, options = OperationOptions(), sources: [URL] = []
                var optionsFile: URL?
                while !args.isEmpty {
                    let flag = args.removeFirst()
                    func value() throws -> String { guard !args.isEmpty else { throw OperationFailure.invalidOptions("\(flag) needs a value.") }; return args.removeFirst() }
                    switch flag {
                    case "--action": guard let id = ActionID(rawValue:try value()) else { throw OperationFailure.invalidOptions("Unknown action identifier.") }; action = id
                    case "--to": target = try value()
                    case "--output": destination = URL(fileURLWithPath:try value(),isDirectory:true)
                    case "--options": optionsFile = URL(fileURLWithPath:try value())
                    case "--quality": guard let q = Double(try value()),(0...1).contains(q) else { throw OperationFailure.invalidOptions("Quality must be between 0 and 1.") }; options.quality = q; options.minimumQuality = min(q,0.3)
                    case "--strip-metadata": options.preserveMetadata = false
                    case "--remove-location": options.removeLocation = true
                    case "--pages": let parts = try value().split(separator:","); let numbers = parts.compactMap { Int($0) }; guard parts.count == numbers.count else { throw OperationFailure.invalidOptions("Pages must be comma-separated integers.") }; options.pages = numbers
                    case "--dpi": guard let dpi = Double(try value()) else { throw OperationFailure.invalidOptions("DPI must be a number.") }; options.dpi = dpi
                    case "--max-dimension": guard let pixels = Int(try value()) else { throw OperationFailure.invalidOptions("Dimension must be an integer.") }; options.maximumDimension = pixels
                    case "--target-bytes": guard let bytes = Int64(try value()) else { throw OperationFailure.invalidOptions("Target size must be an integer.") }; options.targetBytes = bytes
                    case "--allow-downscale": options.allowDownscale = true
                    case "--rotate": guard let degrees = Int(try value()) else { throw OperationFailure.invalidOptions("Rotation must be an integer.") }; options.rotation = degrees
                    case "--offset": guard let seconds = Double(try value()) else { throw OperationFailure.invalidOptions("Offset must be a number.") }; options.subtitleOffset = seconds
                    case "--": sources += args.map { URL(fileURLWithPath:$0) }; args = []
                    default: guard !flag.hasPrefix("--") else { throw OperationFailure.invalidOptions("Unknown option: \(flag)") }; sources.append(URL(fileURLWithPath:flag))
                    }
                }
                if let optionsFile { options = try JSONDecoder().decode(OperationOptions.self,from:Data(contentsOf:optionsFile)) }
                guard !sources.isEmpty, let target else { throw OperationFailure.invalidOptions("Specify --to PROFILE and one or more inputs.") }
                let assets = try await coordinator.inspect(sources)
                guard let descriptor = ActionCatalog.actions(for:assets,installedPacks:Set(packs.map(\.id)),installedOnly:true).first(where: { $0.id == action }),
                      let profile = descriptor.profiles.first(where: { $0.id == target || $0.fileExtension == target || ($0.id == "jpg" && target == "jpeg") }) else { throw OperationFailure.unsupported("This action/profile is unavailable. Use actions INPUT to see installed capabilities.") }
                let batches = descriptor.cardinality == .aggregate ? [sources] : sources.map { [$0] }
                var failed = false
                for batch in batches {
                    do {
                        let manifest = try await coordinator.run(OperationRequest(inputs:batch,action:action,profiles:[profile],options:options,destination:destination))
                        if command == "convert", action == .imageConvert, let result = manifest.outputs.first {
                            let object: [String:Any] = ["source":batch[0].path,"output":result.url.path,"width":result.width ?? 0,"height":result.height ?? 0,"pages":result.pageCount ?? 1,"bytes":result.byteCount,"notices":manifest.notices]
                            print(String(decoding:try JSONSerialization.data(withJSONObject:object,options:.sortedKeys),as:UTF8.self))
                        } else { try emit(manifest) }
                    } catch { failed = true; FileHandle.standardError.write(Data("\(batch[0].lastPathComponent): \(error.localizedDescription)\n".utf8)) }
                }
                if failed { exit(1) }
            default: throw OperationFailure.invalidOptions("Unknown command: \(command)")
            }
        } catch { FileHandle.standardError.write(Data((error.localizedDescription + "\n").utf8)); exit(2) }
    }
    struct Inspection: Encodable { var schemaVersion = 1; var assets: [AssetDescriptor] }
    struct Actions: Encodable { var schemaVersion = 1; var actions: [ActionDescriptor] }
    struct Jobs: Encodable { var schemaVersion = 1; var jobs: [JobRecord] }
    struct Packs: Encodable { var schemaVersion = 1; var packs: [InstalledEnginePack] }
    static func help() {
        print("""
        Local file converter

        convert-file capabilities
        convert-file inspect FILE...
        convert-file actions FILE...
        convert-file convert --to jpg [--quality 0.9] [--strip-metadata] [--output FOLDER] IMAGE...
        convert-file run --action pdf.export --to png [--pages 3,1,2] [--dpi 144] FILE...
        convert-file run --action image.convert --to jpg [--max-dimension 1920] [--target-bytes 1000000] [--allow-downscale] IMAGE...
        convert-file run --action archive.create --to zip FILE...
        convert-file run --action subtitle.convert --to vtt [--offset 1.5] FILE...
        convert-file run --action ACTION --to PROFILE [--options OPTIONS.json] [--output FOLDER] FILE...
        convert-file recipe validate RECIPE.json
        convert-file recipe run RECIPE.json FILE...
        convert-file engines list | install PACK.bundle | verify PACK.bundle
        convert-file jobs [--recover]

        Results are verified and published beside originals unless --output is set.
        Existing files are never replaced. Optional engines require signed packs.
        Desktop conversions use a sandboxed XPC worker. The development CLI uses a separate process.
        """)
    }
}
