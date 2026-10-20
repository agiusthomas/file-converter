import Foundation

public actor JobCoordinator {
    public static var defaultJournal: URL {
        if let path = ProcessInfo.processInfo.environment["FILE_CONVERTER_JOB_DIRECTORY"] { return URL(fileURLWithPath:path,isDirectory:true) }
        return FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("File Converter/Jobs",isDirectory:true)
    }
    private let transport: any WorkerTransport
    private let journal: URL
    private let packs: [InstalledEnginePack]
    private var active = false
    private var enginePins: [String:String] { Dictionary(uniqueKeysWithValues:packs.map { ($0.id,$0.manifest.version) }) }
    private var submitted: [UUID:JobRecord] = [:]
    private var waiters: [(UUID,CheckedContinuation<Void,Error>)] = []
    public init(transport: any WorkerTransport, journal: URL = defaultJournal, packs: [InstalledEnginePack] = []) { self.transport = transport; self.journal = journal; self.packs = packs }
    public func inspect(_ urls: [URL]) async throws -> [AssetDescriptor] {
        guard !urls.isEmpty, urls.count <= 1000 else { throw OperationFailure.resourceLimit }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("inspection-\(UUID().uuidString)",isDirectory:true)
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:false)
        defer { try? FileManager.default.removeItem(at:directory) }
        var staged: [URL] = []
        for (index,url) in urls.enumerated() {
            try Task.checkCancellation()
            let granted = url.startAccessingSecurityScopedResource(); defer { if granted { url.stopAccessingSecurityScopedResource() } }
            let target = directory.appendingPathComponent("\(index)",isDirectory:true)
            try FileManager.default.createDirectory(at:target,withIntermediateDirectories:false)
            let input = target.appendingPathComponent(url.lastPathComponent)
            let values = try url.resourceValues(forKeys:[.isDirectoryKey,.isSymbolicLinkKey])
            guard values.isSymbolicLink != true else { throw OperationFailure.unsupported("Choose original files instead of symbolic links.") }
            if values.isDirectory == true { try FileManager.default.createDirectory(at:input,withIntermediateDirectories:false) } else { try InputSnapshot.copy(url,to:input) }
            staged.append(input)
        }
        let result = try await transport.perform(WorkerEnvelope(inputs:staged,packs:packs))
        if let error = result.error { throw OperationFailure.invalidInput(error) }
        guard let assets = result.assets, assets.count == urls.count else { throw OperationFailure.verification("File inspection returned an incomplete result.") }
        return zip(assets,urls).map { asset,url in var descriptor = AssetDescriptor(source:url,family:asset.family,format:asset.format,byteCount:asset.byteCount); descriptor.width = asset.width; descriptor.height = asset.height; descriptor.pageCount = asset.pageCount; descriptor.duration = asset.duration; descriptor.tracks = asset.tracks; descriptor.notices = asset.notices; descriptor.members = asset.members; descriptor.supportedProfiles = asset.supportedProfiles; descriptor.metadata = asset.metadata; descriptor.nativeDecodable = asset.nativeDecodable; return descriptor }
    }
    private func acquire(_ id: UUID) async throws {
        if !active { active = true; return }
        try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { (continuation:CheckedContinuation<Void,Error>) in
                if Task.isCancelled { continuation.resume(throwing:CancellationError()) } else { waiters.append((id,continuation)) }
            }
        },onCancel:{ Task { await self.cancelWaiter(id) } })
    }
    private func cancelWaiter(_ id: UUID) { if let index = waiters.firstIndex(where: { $0.0 == id }) { waiters.remove(at:index).1.resume(throwing:CancellationError()) } }
    private func release() { if !waiters.isEmpty { waiters.removeFirst().1.resume() } else { active = false } }
    private func persist(_ record: JobRecord) throws {
        try FileManager.default.createDirectory(at:journal,withIntermediateDirectories:true)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(record).write(to:journal.appendingPathComponent(record.id.uuidString + ".json"),options:.atomic)
    }
    private func destination(for request: OperationRequest) throws -> URL {
        guard let first = request.inputs.first else { throw OperationFailure.invalidInput("Choose input files.") }
        var destination = request.destination ?? first.deletingLastPathComponent()
        if let root = request.relativeSourceRoot, request.destination != nil, request.inputs.count == 1 {
            let relative = try PathPolicy.relativePath(of:first.deletingLastPathComponent(),under:root)
            if !relative.isEmpty { _ = try ArchiveEngine.safeName(relative); destination.appendPathComponent(relative,isDirectory:true) }
        }
        return destination
    }
    public func records(recoverInterrupted: Bool = false) throws -> [JobRecord] {
        guard FileManager.default.fileExists(atPath:journal.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(at:journal,includingPropertiesForKeys:nil).filter { $0.pathExtension == "json" }.compactMap { url in
            guard var record = try? JSONDecoder().decode(JobRecord.self,from:Data(contentsOf:url)) else { return nil }
            let ownerIsAlive = record.ownerPID.map { kill($0,0) == 0 || errno == EPERM } ?? false
            if recoverInterrupted, !ownerIsAlive, ![.succeeded,.failed,.cancelled,.interrupted].contains(record.state) {
                record.state = .interrupted; record.error = "Interrupted before completion. Published outputs are preserved; retry unfinished work explicitly."
                if let stage = record.stageDirectory, let destination = try? destination(for:record.request) {
                    let expected = destination.appendingPathComponent(".file-converter-\(record.id.uuidString)")
                    if stage.standardizedFileURL.path == expected.standardizedFileURL.path { try? FileManager.default.removeItem(at:stage) }
                }
                record.stageDirectory = nil
                try persist(record)
            }
            return record
        }.sorted { $0.createdAt < $1.createdAt }
    }
    public func clearFinished() throws {
        for record in try records() where [.succeeded,.failed,.cancelled,.interrupted].contains(record.state) { try FileManager.default.removeItem(at:journal.appendingPathComponent(record.id.uuidString + ".json")) }
    }
    public func submit(_ request: OperationRequest) throws {
        guard !request.inputs.isEmpty, request.inputs.count <= 1000 else { throw OperationFailure.resourceLimit }
        _ = try request.options.validated()
        if FileManager.default.fileExists(atPath:journal.appendingPathComponent(request.id.uuidString + ".json").path) { return }
        var record = JobRecord(request:request); record.pinnedEngines = enginePins; try persist(record); submitted[request.id] = record
    }
    public func cancelSubmitted(_ id: UUID) throws {
        guard var record = submitted.removeValue(forKey:id) else { return }
        record.state = .cancelled; record.error = "Cancelled before execution."; try persist(record)
    }
    public func run(_ request: OperationRequest, progress: (@Sendable (JobState) -> Void)? = nil) async throws -> OutputManifest {
        guard !request.inputs.isEmpty, request.inputs.count <= 1000 else { throw OperationFailure.resourceLimit }
        _ = try request.options.validated()
        let previouslySubmitted = submitted.removeValue(forKey:request.id)
        var record = previouslySubmitted ?? JobRecord(request:request); record.pinnedEngines = enginePins
        guard previouslySubmitted != nil || !FileManager.default.fileExists(atPath:journal.appendingPathComponent(request.id.uuidString + ".json").path) else { throw OperationFailure.invalidOptions("This job already exists. Retry using a new job identifier.") }
        try persist(record); progress?(.queued)
        do { try await acquire(request.id) }
        catch { record.state = .cancelled; record.error = error.localizedDescription; try persist(record); throw error }
        defer { release() }
        var stage: URL?
        var granted: [URL] = []
        defer { granted.forEach { $0.stopAccessingSecurityScopedResource() }; if let stage { try? FileManager.default.removeItem(at:stage) } }
        do {
            try Task.checkCancellation()
            for url in request.inputs + [request.destination ?? request.inputs[0].deletingLastPathComponent()] { if url.startAccessingSecurityScopedResource() { granted.append(url) } }
            let destination = try destination(for:request)
            if request.relativeSourceRoot != nil { try FileManager.default.createDirectory(at:destination,withIntermediateDirectories:true) }
            record.state = .analysing; try persist(record); progress?(.analysing)
            let disk = try destination.resourceValues(forKeys:[.volumeAvailableCapacityForImportantUsageKey,.volumeAvailableCapacityKey])
            var required: Int64 = 0
            for input in request.inputs {
                let values = try input.resourceValues(forKeys:[.isSymbolicLinkKey,.fileSizeKey,.isRegularFileKey,.isDirectoryKey])
                guard values.isSymbolicLink != true, values.isRegularFile == true || values.isDirectory == true else { throw OperationFailure.invalidInput("Unsupported input file.") }
                if values.isDirectory == true {
                    let folder = input.resolvingSymlinksInPath().standardizedFileURL.path, output = destination.resolvingSymlinksInPath().standardizedFileURL.path
                    guard output != folder, !output.hasPrefix(folder + "/") else { throw OperationFailure.invalidOptions("Choose an output folder outside the folder being archived.") }
                }
                required += Int64(values.fileSize ?? 0)
            }
            let available = disk.volumeAvailableCapacityForImportantUsage.flatMap { $0 > 0 ? $0 : nil } ?? disk.volumeAvailableCapacity.map(Int64.init)
            if let available, available > 0, available < min(required,1024*1024*1024) + 16*1024*1024 { throw OperationFailure.process("There is not enough free space for this conversion.") }
            let jobDirectory = destination.appendingPathComponent(".file-converter-\(request.id.uuidString)",isDirectory:true)
            try FileManager.default.createDirectory(at:jobDirectory,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700]); stage = jobDirectory
            record.stageDirectory = jobDirectory; try persist(record)
            let inputDirectory = jobDirectory.appendingPathComponent("inputs",isDirectory:true), outputDirectory = jobDirectory.appendingPathComponent("outputs",isDirectory:true)
            try FileManager.default.createDirectory(at:inputDirectory,withIntermediateDirectories:false)
            try FileManager.default.createDirectory(at:outputDirectory,withIntermediateDirectories:false)
            var staged = request; staged.inputs = []; staged.destination = outputDirectory
            var mapping: [String:URL] = [:]
            for (index,source) in request.inputs.enumerated() {
                try Task.checkCancellation()
                let folder = inputDirectory.appendingPathComponent(String(index),isDirectory:true)
                try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:false)
                let target = folder.appendingPathComponent(source.lastPathComponent)
                try InputSnapshot.copy(source,to:target)
                staged.inputs.append(target); mapping[target.standardizedFileURL.path] = source
            }
            record.state = .running; try persist(record); progress?(.running)
            let response = try await transport.perform(WorkerEnvelope(inputs:staged.inputs,request:staged,directory:outputDirectory,packs:packs))
            if let error = response.error { throw OperationFailure.process(error) }
            guard let manifest = response.manifest, manifest.jobID == request.id, !manifest.outputs.isEmpty else { throw OperationFailure.verification("The worker returned an invalid output manifest.") }
            record.state = .validating; try persist(record); progress?(.validating)
            let checked = try checkedOutputs(manifest,directory:outputDirectory,mapping:mapping)
            record.state = .publishing; record.manifest = OutputManifest(jobID:request.id,outputs:[],notices:manifest.notices,engine:manifest.engine)
            record.manifest?.engineVersions = manifest.engineVersions
            try persist(record); progress?(.publishing)
            for var artifact in checked {
                try Task.checkCancellation()
                artifact.url = try AtomicPublisher.publish(stagedItem:artifact.url,directory:destination,preferredName:artifact.url.lastPathComponent)
                record.manifest?.outputs.append(artifact); try persist(record)
            }
            record.state = .succeeded; record.stageDirectory = nil; try persist(record); progress?(.succeeded)
            return record.manifest!
        } catch {
            record.state = error is CancellationError ? .cancelled : .failed; record.error = error.localizedDescription; record.stageDirectory = nil
            try persist(record); progress?(record.state); throw error
        }
    }
    public func run(_ recipe: Recipe, inputs: [URL], destination: URL? = nil, skippingExports: Set<Int> = [], completedOutputs: [OutputArtifact] = []) async throws -> OutputManifest {
        try recipe.validate()
        guard let source = inputs.first, inputs.count <= 1000 else { throw OperationFailure.invalidInput("Choose up to 1,000 recipe inputs.") }
        let output = destination ?? source.deletingLastPathComponent()
        var record = JobRecord(request:OperationRequest(inputs:inputs,action:recipe.steps[0].action,profiles:recipe.steps[0].profiles,destination:output))
        record.recipe = recipe.redacted; record.pinnedEngines = enginePins; record.completedRecipeExports = Array(skippingExports).sorted()
        try persist(record)
        do { try await acquire(record.id) } catch { record.state = .cancelled; record.error = error.localizedDescription; try persist(record); throw error }
        defer { release() }
        let granted = output.startAccessingSecurityScopedResource()
        defer { if granted { output.stopAccessingSecurityScopedResource() } }
        let temporary = output.appendingPathComponent(".file-converter-\(record.id.uuidString)",isDirectory:true)
        defer { try? FileManager.default.removeItem(at:temporary) }
        do {
            try Task.checkCancellation()
            try FileManager.default.createDirectory(at:temporary,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700])
            record.stageDirectory = temporary; record.state = .analysing; try persist(record)
            var current: [URL] = [], lineage: [String:[URL]] = [:]
            for (index,input) in inputs.enumerated() {
                let granted = input.startAccessingSecurityScopedResource(); defer { if granted { input.stopAccessingSecurityScopedResource() } }
                let folder = temporary.appendingPathComponent("source-\(index)",isDirectory:true)
                try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:false)
                let staged = folder.appendingPathComponent(input.lastPathComponent)
                try InputSnapshot.copy(input,to:staged); current.append(staged); lineage[staged.standardizedFileURL.path] = [input]
            }
            record.manifest = OutputManifest(jobID:record.id,outputs:[])
            for (index,step) in recipe.steps.enumerated() {
                try Task.checkCancellation()
                if step.export && skippingExports.contains(index) { continue }
                record.state = .running; try persist(record)
                let manifest = try await makePreview(OperationRequest(inputs:current,action:step.action,profiles:step.profiles,options:step.options),in:temporary.appendingPathComponent("step-\(index)"))
                record.manifest?.notices += manifest.notices
                let versions = (record.manifest?.engineVersions ?? [:]).merging(manifest.engineVersions ?? [:],uniquingKeysWith:{$1}); record.manifest?.engineVersions = versions
                var results: [OutputArtifact] = []
                for var artifact in manifest.outputs {
                    var seen = Set<URL>()
                    artifact.sources = artifact.sources.flatMap { lineage[$0.standardizedFileURL.path] ?? [] }.filter { seen.insert($0).inserted }
                    guard !artifact.sources.isEmpty else { throw OperationFailure.verification("Recipe output has no source relationship.") }
                    lineage[artifact.url.standardizedFileURL.path] = artifact.sources; results.append(artifact)
                }
                if step.export {
                    record.state = .publishing; try persist(record)
                    var alreadyPublished = completedOutputs.filter { $0.recipeStep == index }
                    for var artifact in results {
                        try Task.checkCancellation()
                        if let prior = alreadyPublished.firstIndex(where:{$0.format == artifact.format && $0.sources == artifact.sources}) { alreadyPublished.remove(at:prior); continue }
                        artifact.recipeStep = index
                        artifact.url = try AtomicPublisher.publish(stagedItem:artifact.url,directory:output,preferredName:artifact.url.lastPathComponent)
                        record.manifest?.outputs.append(artifact); try persist(record)
                    }
                    record.completedRecipeExports?.append(index); try persist(record)
                } else {
                    current = []
                    for artifact in results {
                        if (try artifact.url.resourceValues(forKeys:[.isDirectoryKey]).isDirectory) == true,
                           index + 1 < recipe.steps.count, recipe.steps[index+1].action != .archiveCreate {
                            guard let iterator = FileManager.default.enumerator(at:artifact.url,includingPropertiesForKeys:[.isRegularFileKey,.isSymbolicLinkKey]) else { throw OperationFailure.invalidInput("Cannot read recipe intermediate files.") }
                            while let child = iterator.nextObject() as? URL {
                                let values = try child.resourceValues(forKeys:[.isRegularFileKey,.isSymbolicLinkKey])
                                guard values.isSymbolicLink != true else { throw OperationFailure.verification("Recipe intermediate contains a link.") }
                                if values.isRegularFile == true { current.append(child); lineage[child.standardizedFileURL.path] = artifact.sources }
                                guard current.count <= 1000 else { throw OperationFailure.resourceLimit }
                            }
                        } else { current.append(artifact.url) }
                    }
                    current.sort { $0.path < $1.path }
                }
            }
            record.state = .succeeded; record.stageDirectory = nil; try persist(record)
            return record.manifest!
        } catch {
            record.state = error is CancellationError ? .cancelled : .failed; record.error = error.localizedDescription; record.stageDirectory = nil; try persist(record); throw error
        }
    }
    public func preview(_ request: OperationRequest, in directory: URL) async throws -> OutputManifest {
        try await acquire(request.id); defer { release() }
        return try await makePreview(request,in:directory)
    }
    private func makePreview(_ request: OperationRequest, in directory: URL) async throws -> OutputManifest {
        guard !request.inputs.isEmpty, request.inputs.count <= 1000 else { throw OperationFailure.resourceLimit }
        _ = try request.options.validated(); try Task.checkCancellation()
        var complete = false
        defer { if !complete { try? FileManager.default.removeItem(at:directory) } }
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:false)
        let inputs = directory.appendingPathComponent("inputs",isDirectory:true), outputs = directory.appendingPathComponent("outputs",isDirectory:true)
        try FileManager.default.createDirectory(at:inputs,withIntermediateDirectories:false); try FileManager.default.createDirectory(at:outputs,withIntermediateDirectories:false)
        var copy = request; copy.inputs = []; copy.destination = outputs
        var mapping: [String:URL] = [:]
        for (index,url) in request.inputs.enumerated() {
            try Task.checkCancellation()
            let granted = url.startAccessingSecurityScopedResource(); defer { if granted { url.stopAccessingSecurityScopedResource() } }
            let child = inputs.appendingPathComponent("\(index)",isDirectory:true); try FileManager.default.createDirectory(at:child,withIntermediateDirectories:false)
            let staged = child.appendingPathComponent(url.lastPathComponent); try InputSnapshot.copy(url,to:staged); copy.inputs.append(staged); mapping[staged.standardizedFileURL.path] = url
        }
        let response = try await transport.perform(WorkerEnvelope(inputs:copy.inputs,request:copy,directory:outputs,packs:packs))
        if let error = response.error { throw OperationFailure.process(error) }
        guard var manifest = response.manifest, manifest.jobID == request.id, !manifest.outputs.isEmpty else { throw OperationFailure.verification("Preview did not produce a valid result.") }
        manifest.outputs = try checkedOutputs(manifest,directory:outputs,mapping:mapping)
        complete = true; return manifest
    }
    private func checkedOutputs(_ manifest: OutputManifest, directory outputDirectory: URL, mapping: [String:URL]) throws -> [OutputArtifact] {
        guard manifest.outputs.count <= 1000 else { throw OperationFailure.resourceLimit }
        var checked: [OutputArtifact] = []; var seen = Set<URL>()
        for var artifact in manifest.outputs {
                try Task.checkCancellation()
                let resolved = artifact.url.resolvingSymlinksInPath().standardizedFileURL
                guard resolved.path.hasPrefix(outputDirectory.resolvingSymlinksInPath().standardizedFileURL.path + "/"), artifact.validated, !artifact.sources.isEmpty, !seen.contains(where: { resolved.path.hasPrefix($0.path + "/") || $0.path.hasPrefix(resolved.path + "/") }), seen.insert(resolved).inserted, artifact.sources.allSatisfy({ mapping[$0.standardizedFileURL.path] != nil }) else { throw OperationFailure.verification("The worker returned an unsafe or duplicate output path.") }
                let values = try artifact.url.resourceValues(forKeys:[.isSymbolicLinkKey,.isDirectoryKey,.isRegularFileKey,.fileSizeKey])
                guard values.isSymbolicLink != true, values.isRegularFile == true || values.isDirectory == true else { throw OperationFailure.verification("An output is not a regular file or folder.") }
                if values.isRegularFile == true {
                    guard artifact.byteCount == Int64(values.fileSize ?? -1) else { throw OperationFailure.verification("Output size changed after worker validation.") }
                    let hash = try FileDigest.sha256(artifact.url)
                    guard artifact.sha256 == nil || artifact.sha256 == hash else { throw OperationFailure.verification("An output changed after validation.") }
                    artifact.sha256 = hash
                } else {
                    guard let iterator = FileManager.default.enumerator(at:artifact.url,includingPropertiesForKeys:[.isSymbolicLinkKey,.isDirectoryKey,.isRegularFileKey,.fileSizeKey]) else { throw OperationFailure.verification("Cannot inspect output folder.") }
                    var bytes: Int64 = 0, count = 0
                    while let child = iterator.nextObject() as? URL {
                        try Task.checkCancellation(); count += 1; guard count <= 10000 else { throw OperationFailure.resourceLimit }
                        let values = try child.resourceValues(forKeys:[.isSymbolicLinkKey,.isDirectoryKey,.isRegularFileKey,.fileSizeKey])
                        guard values.isSymbolicLink != true, values.isDirectory == true || values.isRegularFile == true else { throw OperationFailure.verification("An output folder contains a link or special file.") }
                        if values.isRegularFile == true { bytes += Int64(values.fileSize ?? 0) }
                        guard bytes <= 16*1024*1024*1024 else { throw OperationFailure.resourceLimit }
                    }
                    guard bytes == artifact.byteCount else { throw OperationFailure.verification("Output folder size changed after validation.") }
                }
                artifact.sources = artifact.sources.compactMap { mapping[$0.standardizedFileURL.path] }; checked.append(artifact)
            }
        return checked
    }
}
