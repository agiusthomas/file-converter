import AppKit
import Combine
import ConverterCore
import ServiceManagement

enum WorkspacePage: String, CaseIterable { case convert = "Convert", activity = "Activity", recipes = "Recipes", shelf = "Shelf", engines = "Engines", settings = "Settings" }
@MainActor final class AppModel: ObservableObject {
    let registry = CapabilityRegistry()
    let coordinator: JobCoordinator
    @Published var page: WorkspacePage = .convert
    @Published var sources: [URL] = []
    @Published var assets: [AssetDescriptor] = []
    @Published var selectedAction: ActionID = .imageConvert
    @Published var selectedProfileID = "jpg"
    @Published var additionalProfiles: Set<String> = []
    @Published var options = OperationOptions() { didSet { UserDefaults.standard.set(options.quality,forKey:"quality"); UserDefaults.standard.set(options.preserveMetadata,forKey:"preserveMetadata") } }
    @Published var jobs: [JobRecord] = []
    @Published var isProcessing = false
    @Published var isInspecting = false
    @Published var isCancelling = false
    @Published var message: String?
    @Published var destination: URL?
    @Published var previewURL: URL?
    @Published var resultPreviewURL: URL?
    @Published var previewSummary: String?
    @Published var isPreviewing = false
    @Published var pageThumbnails: [URL] = []
    @Published var isLoadingPages = false
    private var thumbnailDirectory: URL?
    private var thumbnailTask: Task<Void,Never>?
    private var previewTask: Task<Void,Never>?
    private var previewDirectory: URL?
    @Published var recipes: [Recipe] = []
    @Published var packs: [InstalledEnginePack]
    @Published var engineCatalog: [EngineDownload] = []
    @Published var storedPacks: [InstalledEnginePack] = []
    @Published var engineRollbackVersions: [String:String] = [:]
    @Published var engineRemovals: Set<String> = []
    @Published var engineBusyID: String?
    @Published var engineProgress: EngineDownloadProgress?
    @Published var engineFailure: String?
    private var engineTask: Task<Void,Never>?
    private var engineRemovalTask: Task<Void,Never>?
    private var engineRefreshPending = false
    @Published var watchRules: [WatchRule] = []
    @Published var shelf: [URL] = []
    @Published var relativeSourceRoot: URL?
    private lazy var watcher = WatchedFolderRunner(coordinator:coordinator)
    @Published var wheelEnabled: Bool { didSet { UserDefaults.standard.set(wheelEnabled,forKey:"wheelEnabled"); onWheelSettingChanged?(wheelEnabled) } }
    @Published var modifier: String { didSet { UserDefaults.standard.set(modifier,forKey:"wheelModifier"); onModifierChanged?(modifier) } }
    @Published var launchAtLogin = SMAppService.mainApp.status == .enabled
    var onWheelSettingChanged: ((Bool) -> Void)?
    var onModifierChanged: ((String) -> Void)?
    var onShowWheel: (([URL]) -> Void)?
    var onShowWindow: (() -> Void)?
    private var queueTask: Task<Void,Never>?
    private var inspectionTask: Task<Void,Never>?
    private var selectionID = UUID()
    private var pending: [OperationRequest] = []
    private var recipeTask: Task<Void,Never>?
    var actions: [ActionDescriptor] { ActionCatalog.actions(for:assets,installedPacks:Set(packs.map(\.id))) }
    var action: ActionDescriptor? { actions.first { $0.id == selectedAction } }
    var profiles: [OutputProfile] { action?.profiles ?? [] }
    var selectedProfile: OutputProfile? { profiles.first { $0.id == selectedProfileID } }
    var completedCount: Int { jobs.filter { $0.state == .succeeded }.count }
    var failedCount: Int { jobs.filter { [.failed,.interrupted].contains($0.state) }.count }
    var activeCount: Int { jobs.filter { ![.succeeded,.failed,.cancelled,.interrupted].contains($0.state) }.count }
    var progress: Double { jobs.isEmpty ? 0 : Double(jobs.count-activeCount)/Double(jobs.count) }
    init(coordinator: JobCoordinator? = nil) {
        UserDefaults.standard.register(defaults:["wheelEnabled":true,"wheelModifier":"shift","quality":0.9,"preserveMetadata":true])
        wheelEnabled = UserDefaults.standard.bool(forKey:"wheelEnabled"); modifier = UserDefaults.standard.string(forKey:"wheelModifier") ?? "shift"
        let installed = EnginePacks.installed(); packs = installed
        if let coordinator { self.coordinator = coordinator }
        else {
            let worker = Bundle.main.bundleURL.appendingPathComponent("Contents/XPCServices/ConversionWorker.xpc")
            let transport: any WorkerTransport = FileManager.default.fileExists(atPath:worker.path) ? XPCWorkerTransport() : ProcessWorkerTransport(executable:URL(fileURLWithPath:CommandLine.arguments[0]).deletingLastPathComponent().appendingPathComponent("converter-worker"))
            self.coordinator = JobCoordinator(transport:transport,packs:installed)
        }
        options.quality = UserDefaults.standard.double(forKey:"quality"); options.preserveMetadata = UserDefaults.standard.bool(forKey:"preserveMetadata")
        if let data = UserDefaults.standard.data(forKey:"recipes"), let saved = try? JSONDecoder().decode([Recipe].self,from:data) { recipes = saved } else { recipes = Self.starterRecipes }
        if let data = UserDefaults.standard.data(forKey:"watchRules"), let rules = try? JSONDecoder().decode([WatchRule].self,from:data) { watchRules = rules }
        let shelfBookmarks = UserDefaults.standard.array(forKey:"shelfBookmarks") as? [Data] ?? []
        shelf = shelfBookmarks.compactMap { data in var stale = false; return try? URL(resolvingBookmarkData:data,options:.withSecurityScope,relativeTo:nil,bookmarkDataIsStale:&stale) }
        // Injected coordinators own their isolated session; normal app startup
        // restores saved history, engine state and watched folders.
        if coordinator == nil {
            Task { try? await Task.detached { try TransientWorkspace.removeExpired() }.value; await refreshHistory(recover:true); await refreshEngineLibrary(); restartWatchers() }
        }
    }
    static var starterRecipes: [Recipe] {
        var screenshot = OperationOptions(); screenshot.maximumDimension = 1920; screenshot.preserveMetadata = false; screenshot.targetBytes = 2*1024*1024; screenshot.allowDownscale = true
        var recording = OperationOptions(); recording.maximumDimension = 1280
        return [Recipe(name:"Share screenshots",steps:[.init(action:.imageConvert,profiles:[ActionCatalog.jpg],options:screenshot,export:true)]), Recipe(name:"Smaller recordings",steps:[.init(action:.mediaConvert,profiles:[ActionCatalog.mp4],options:recording,export:true)]), Recipe(name:"Searchable scans",steps:[.init(action:.pdfOCR,profiles:[.init("searchable-pdf","Searchable PDF","pdf")],export:true)]), Recipe(name:"Office to PDF",steps:[.init(action:.documentConvert,profiles:[ActionCatalog.pdf],export:true)])]
    }
    func inspect(_ urls: [URL]) async throws -> [AssetDescriptor] { try await coordinator.inspect(urls) }
    func setSources(_ urls: [URL]) {
        cancelPreview()
        thumbnailTask?.cancel(); pageThumbnails = []; isLoadingPages = false
        if let thumbnailDirectory { try? FileManager.default.removeItem(at:thumbnailDirectory) }; thumbnailDirectory = nil
        options.pages = []; options.pageRotations = [:]
        options.inputPassword = nil; options.outputPassword = nil
        if let root = relativeSourceRoot, !urls.allSatisfy({$0.standardizedFileURL.path.hasPrefix(root.standardizedFileURL.path + "/")}) { relativeSourceRoot = nil }
        inspectionTask?.cancel(); let id = UUID(); selectionID = id
        sources = Array(NSOrderedSet(array:urls)) as? [URL] ?? urls; assets = []; additionalProfiles = []
        guard !sources.isEmpty else { isInspecting = false; return }
        let selection = sources; isInspecting = true; message = nil; page = .convert
        inspectionTask = Task {
            do {
                let inspected = try await coordinator.inspect(selection)
                guard selectionID == id, !Task.isCancelled else { return }
                assets = inspected
                if !actions.contains(where: { $0.id == selectedAction && $0.available }), let first = actions.first(where: \.available) { selectAction(first.id) } else { selectAction(selectedAction) }
                previewURL = selection.first
            } catch { if selectionID == id && !Task.isCancelled { message = error.localizedDescription } }
            if selectionID == id { isInspecting = false }
        }
    }
    func selectAction(_ id: ActionID) { selectedAction = id; additionalProfiles = []; if !profiles.contains(where: { $0.id == selectedProfileID }) { selectedProfileID = profiles.first?.id ?? "" } }
    func pickFiles(showWheel: Bool = false) {
        let panel = NSOpenPanel(); panel.title = "Choose files or folders"; panel.prompt = "Choose files"; panel.allowsMultipleSelection = true; panel.canChooseDirectories = true; panel.canChooseFiles = true
        guard panel.runModal() == .OK else { return }; setSources(panel.urls); if showWheel { onShowWheel?(panel.urls) }
    }
    func convertSelection() {
        cancelPreview(); thumbnailTask?.cancel(); isLoadingPages = false
        guard let action, action.available, let profile = selectedProfile, !isInspecting else { return }
        var settings = options; settings.minimumQuality = min(settings.quality,settings.minimumQuality)
        let chosen = [profile] + profiles.filter { additionalProfiles.contains($0.id) && $0.id != profile.id }
        if action.cardinality == .aggregate { enqueue(OperationRequest(inputs:sources,action:action.id,profiles:chosen,options:settings,destination:destination)) }
        else { for (index,source) in sources.enumerated() { var perFile = settings; perFile.sequence = index+1; var request = OperationRequest(inputs:[source],action:action.id,profiles:chosen,options:perFile,destination:destination); request.relativeSourceRoot = relativeSourceRoot; enqueue(request) } }
    }
    func cancelPreview() { previewTask?.cancel(); previewTask = nil; isPreviewing = false; resultPreviewURL = nil; previewSummary = nil; if let previewDirectory { try? FileManager.default.removeItem(at:previewDirectory) }; previewDirectory = nil }
    func previewResult() {
        guard let profile = selectedProfile, let source = sources.first, !isProcessing else { return }
        cancelPreview(); isPreviewing = true
        guard let directory = try? TransientWorkspace.url(prefix:"preview") else { isPreviewing = false; message = "A preview workspace could not be created."; return }
        previewDirectory = directory
        var settings = options; settings.minimumQuality = min(settings.quality,settings.minimumQuality)
        let request = OperationRequest(inputs:modelPreviewInputs(source),action:selectedAction,profiles:[profile],options:settings)
        previewTask = Task {
            do {
                let manifest = try await coordinator.preview(request,in:directory)
                guard !Task.isCancelled else { return }
                resultPreviewURL = manifest.outputs.first?.url
                previewSummary = manifest.outputs.map { ByteCountFormatter.string(fromByteCount:$0.byteCount,countStyle:.file) }.joined(separator:", ")
            } catch { if !Task.isCancelled { message = error.localizedDescription } }
            isPreviewing = false
        }
    }
    private func modelPreviewInputs(_ first: URL) -> [URL] { action?.cardinality == .aggregate ? sources : [first] }
    func loadPageThumbnails() {
        guard sources.count == 1, assets.first?.family == .pdf, !isProcessing, !isLoadingPages else { return }
        isLoadingPages = true
        guard let directory = try? TransientWorkspace.url(prefix:"thumbnails") else { isLoadingPages = false; message = "A thumbnail workspace could not be created."; return }
        thumbnailDirectory = directory
        var settings = OperationOptions(); settings.dpi = 36; settings.inputPassword = options.inputPassword
        let request = OperationRequest(inputs:sources,action:.pdfExport,profiles:[ActionCatalog.png],options:settings)
        thumbnailTask = Task {
            do {
                let result = try await coordinator.preview(request,in:directory)
                guard !Task.isCancelled, let folder = result.outputs.first?.url else { return }
                pageThumbnails = try FileManager.default.contentsOfDirectory(at:folder,includingPropertiesForKeys:nil).sorted { $0.lastPathComponent < $1.lastPathComponent }
                if options.pages.isEmpty { options.pages = Array(1...pageThumbnails.count) }
            } catch { if !Task.isCancelled { message = error.localizedDescription } }
            isLoadingPages = false
        }
    }
    func performWheel(_ urls: [URL], choice: WheelChoice) {
        if choice.needsOptions { setSources(urls); selectedAction = choice.action; selectedProfileID = choice.profile.id; onShowWindow?(); return }
        if choice.aggregate { enqueue(OperationRequest(inputs:urls,action:choice.action,profiles:[choice.profile]), showWindow: false) }
        else { for url in urls { enqueue(OperationRequest(inputs:[url],action:choice.action,profiles:[choice.profile]), showWindow: false) } }
    }
    func enqueue(_ request: OperationRequest, showWindow: Bool = true) {
        guard !isCancelling else { return }; pending.append(request); jobs.append(JobRecord(request:request))
        if showWindow { onShowWindow?() }
        message = nil
        Task {
            do { try await coordinator.submit(request); if pending.contains(where:{$0.id == request.id}) { startQueue() } else { try await coordinator.cancelSubmitted(request.id) } }
            catch { pending.removeAll {$0.id == request.id}; if let index = jobs.firstIndex(where:{$0.id == request.id}) { jobs[index].state = .failed; jobs[index].error = error.localizedDescription } }
        }
    }
    private func startQueue() {
        guard queueTask == nil else { return }; isProcessing = true
        queueTask = Task {
            while !pending.isEmpty && !Task.isCancelled {
                let request = pending.removeFirst()
                do {
                    let result = try await coordinator.run(request) { [weak self] state in Task { @MainActor in if let index = self?.jobs.firstIndex(where: { $0.id == request.id }), let current = self?.jobs[index].state, ![.succeeded,.failed,.cancelled,.interrupted].contains(current) { self?.jobs[index].state = state } } }
                    if let index = jobs.firstIndex(where: { $0.id == request.id }) { jobs[index].state = .succeeded; jobs[index].manifest = result }
                } catch { if let index = jobs.firstIndex(where: { $0.id == request.id }) { jobs[index].state = error is CancellationError ? .cancelled : .failed; jobs[index].error = error.localizedDescription } }
            }
            for request in pending { try? await coordinator.cancelSubmitted(request.id); if let index = jobs.firstIndex(where: { $0.id == request.id }) { jobs[index].state = .cancelled } }
            pending = []; await refreshHistory(); isProcessing = false; isCancelling = false; queueTask = nil
            if engineRefreshPending { await refreshEngineLibrary() }
        }
    }
    func cancel() { isCancelling = true; queueTask?.cancel(); recipeTask?.cancel() }
    func retry(_ job: JobRecord) {
        if let recipe = job.recipe { runRecipe(recipe,inputs:job.request.inputs,destination:job.request.destination,skippingExports:Set(job.completedRecipeExports ?? []),completedOutputs:job.manifest?.outputs ?? []) }
        else {
            var request = job.request; request.id = UUID()
            if let saved = job.manifest?.outputs, !saved.isEmpty, request.inputs.count == 1 {
                if request.action == .imageConvert { request.profiles.removeAll { profile in saved.contains(where:{$0.format == profile.fileExtension}) } }
                else { message = "The requested output was already saved. Find it in Activity."; return }
            }
            guard !request.profiles.isEmpty else { message = "All requested outputs were already saved. Find them in Activity."; return }
            enqueue(request)
        }
    }
    func clearFinished() { Task { do { try await coordinator.clearFinished(); jobs.removeAll { [.succeeded,.failed,.cancelled,.interrupted].contains($0.state) } } catch { message = error.localizedDescription } } }
    private func refreshHistory(recover: Bool = false) async {
        do { let saved = try await coordinator.records(recoverInterrupted:recover); let ids = Set(saved.map(\.id)); jobs = (saved + jobs.filter { !ids.contains($0.id) }).sorted { $0.createdAt < $1.createdAt } } catch { message = "Activity could not be loaded: \(error.localizedDescription)" }
    }
    func chooseDestination() {
        let panel = NSOpenPanel(); panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.canCreateDirectories = true; panel.prompt = "Save here"
        guard panel.runModal() == .OK else { return }; destination = panel.url; if let url = panel.url { FolderGrants.shared.save(url) }
    }
    func expandSelectedFolders() {
        guard sources.count == 1, let folder = sources.first, (try? folder.resourceValues(forKeys:[.isDirectoryKey]).isDirectory) == true else { return }
        guard let enumerator = FileManager.default.enumerator(at:folder,includingPropertiesForKeys:[.isRegularFileKey,.isSymbolicLinkKey],options:[.skipsHiddenFiles,.skipsPackageDescendants]) else { return }
        var files: [URL] = []
        while let url = enumerator.nextObject() as? URL {
            if (try? url.resourceValues(forKeys:[.isRegularFileKey,.isSymbolicLinkKey])).map({$0.isRegularFile == true && $0.isSymbolicLink != true}) == true { files.append(url) }
            if files.count > 1000 { message = "Choose a folder with at most 1,000 files for a conversion batch."; return }
        }
        relativeSourceRoot = folder; setSources(files.sorted {$0.path < $1.path})
    }
    func allowOutputFolder() { chooseDestination() }
    func reveal(_ url: URL) { NSWorkspace.shared.activateFileViewerSelecting([url]) }
    func revealAll() { NSWorkspace.shared.activateFileViewerSelecting(jobs.flatMap { $0.manifest?.outputs.map(\.url) ?? [] }) }
    func copy(_ url: URL) { NSPasteboard.general.clearContents(); NSPasteboard.general.writeObjects([url as NSURL]) }
    func setLogin(_ enabled: Bool) { do { if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }; launchAtLogin = SMAppService.mainApp.status == .enabled } catch { message = "Login launch could not be changed: \(error.localizedDescription)" } }
    func saveRecipe(name: String) {
        guard let profile = selectedProfile else { return }; var settings = options; settings.inputPassword = nil; settings.outputPassword = nil
        let outputs = [profile] + profiles.filter { additionalProfiles.contains($0.id) && $0.id != profile.id }
        let recipe = Recipe(name:name,steps:[.init(action:selectedAction,profiles:outputs,options:settings,export:true)])
        do { try recipe.validate(); recipes.append(recipe); persistRecipes() } catch { message = error.localizedDescription }
    }
    func saveEditedRecipe(_ recipe: Recipe) {
        do { try recipe.validate(); if let index = recipes.firstIndex(where:{$0.id == recipe.id}) { recipes[index] = recipe.redacted } else { recipes.append(recipe.redacted) }; persistRecipes() } catch { message = error.localizedDescription }
    }
    func importRecipe() {
        let panel = NSOpenPanel(); panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { guard (try url.resourceValues(forKeys:[.fileSizeKey]).fileSize ?? 0) <= 1024*1024 else { throw OperationFailure.resourceLimit }; var recipe = try JSONDecoder().decode(Recipe.self,from:Data(contentsOf:url)); recipe.id = UUID(); saveEditedRecipe(recipe) } catch { message = error.localizedDescription }
    }
    func exportRecipe(_ recipe: Recipe) {
        let panel = NSSavePanel(); panel.nameFieldStringValue = recipe.name + ".json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted,.sortedKeys]; try encoder.encode(recipe.redacted).write(to:url,options:.atomic) } catch { message = error.localizedDescription }
    }
    func persistRecipes() { do { UserDefaults.standard.set(try JSONEncoder().encode(recipes),forKey:"recipes") } catch { message = error.localizedDescription } }
    func restartWatchers() {
        do { UserDefaults.standard.set(try JSONEncoder().encode(watchRules),forKey:"watchRules") } catch { message = error.localizedDescription }
        let rules = watchRules
        Task { await watcher.start(rules) { [weak self] event in Task { @MainActor in self?.message = event; await self?.refreshHistory(); if self?.engineRefreshPending == true { await self?.refreshEngineLibrary() } } } }
    }
    func addWatchRule(_ recipe: Recipe) {
        let panel = NSOpenPanel(); panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.prompt = "Watch folder"
        guard panel.runModal() == .OK, let folder = panel.url else { return }
        let filters: [String]
        switch recipe.steps.first?.action { case .imageConvert,.imagesToPDF: filters = ["png","jpg","jpeg","heic","tiff","webp","avif"]; case .pdfOCR,.pdfText,.pdfCompress: filters = ["pdf"]; case .mediaConvert,.mediaExtractAudio: filters = ["mov","mp4","wav","m4a","mp3"]; case .documentConvert: filters = ["docx","odt","rtf","pptx","xlsx"]; default: filters = [] }
        FolderGrants.shared.save(folder); watchRules.append(WatchRule(folder:folder,recipe:recipe,extensions:filters)); restartWatchers()
    }
    func shelve(_ url: URL) { guard !shelf.contains(url) else { return }; shelf.append(url); persistShelf() }
    func persistShelf() { UserDefaults.standard.set(shelf.compactMap { try? $0.bookmarkData(options:.withSecurityScope,includingResourceValuesForKeys:nil,relativeTo:nil) },forKey:"shelfBookmarks") }
    func removeGenerated(_ output: OutputArtifact) {
        guard let expected = output.sha256 else { message = "Safe removal is available for verified individual files. Remove output folders through Finder."; return }
        Task {
            do {
                let actual = try await Task.detached { try FileDigest.sha256(output.url) }.value
                guard actual == expected else { message = "The result has changed since conversion, so it was kept."; return }
                NSWorkspace.shared.recycle([output.url]) { [weak self] _,error in Task { @MainActor in self?.message = error.map { $0.localizedDescription } ?? "Generated result moved to Trash. Originals are unchanged." } }
            } catch { message = error.localizedDescription }
        }
    }
    func runRecipe(_ recipe: Recipe) { runRecipe(recipe,inputs:sources,destination:destination) }
    private func runRecipe(_ recipe: Recipe, inputs: [URL], destination: URL?, skippingExports: Set<Int> = [], completedOutputs: [OutputArtifact] = []) {
        guard !inputs.isEmpty, recipeTask == nil else { return }; cancelPreview(); thumbnailTask?.cancel(); isLoadingPages = false; isProcessing = true
        recipeTask = Task { do { _ = try await coordinator.run(recipe,inputs:inputs,destination:destination,skippingExports:skippingExports,completedOutputs:completedOutputs) } catch { message = error.localizedDescription }; await refreshHistory(); recipeTask = nil; isProcessing = queueTask != nil; isCancelling = false; if engineRefreshPending { await refreshEngineLibrary() } }
    }
    func importPack() {
        guard engineTask == nil else { return }
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.treatsFilePackagesAsDirectories = true; panel.prompt = "Install pack"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        changeEngine("local") { _ = try await EnginePacks.importPack(url) }
    }
    func refreshEngineLibrary() async {
        do {
            let result = try await Task.detached {
                _ = try EnginePacks.collectRemovals()
                let catalog = try EnginePacks.catalog(), installed = EnginePacks.installed()
                let rollback = Dictionary(uniqueKeysWithValues:installed.compactMap { pack in EnginePacks.rollbackVersion(pack.id).map { (pack.id,$0) } })
                return (catalog,installed,rollback)
            }.value
            engineCatalog = result.0; storedPacks = result.1; engineRollbackVersions = result.2
            if !isProcessing, pending.isEmpty, try await coordinator.refreshPacks(result.1) {
                let changed = Dictionary(uniqueKeysWithValues:packs.map { ($0.id,$0.manifest.version) }) != Dictionary(uniqueKeysWithValues:result.1.map { ($0.id,$0.manifest.version) })
                packs = result.1; engineRefreshPending = false
                if changed { refreshEngineAssets() }
            } else { engineRefreshPending = true }
            engineRemovals = try await Task.detached { try EnginePacks.collectRemovals() }.value
            finishDeferredEngineRemovals()
        } catch { engineFailure = error.localizedDescription }
    }
    private func finishDeferredEngineRemovals() {
        guard engineRemovalTask == nil, !engineRemovals.isEmpty else { return }
        engineRemovalTask = Task {
            defer { engineRemovalTask = nil }
            while !Task.isCancelled, !engineRemovals.isEmpty {
                do {
                    try await Task.sleep(nanoseconds:1_000_000_000)
                    engineRemovals = try await Task.detached { try EnginePacks.collectRemovals() }.value
                } catch is CancellationError { return }
                catch { engineFailure = error.localizedDescription; return }
            }
        }
    }
    private func refreshEngineAssets() {
        guard !sources.isEmpty else { return }
        inspectionTask?.cancel(); let id = UUID(); selectionID = id
        let selection = sources; isInspecting = true
        inspectionTask = Task {
            do {
                let inspected = try await coordinator.inspect(selection)
                guard selectionID == id, !Task.isCancelled else { return }
                assets = inspected
                if !actions.contains(where:{$0.id == selectedAction && $0.available}), let first = actions.first(where:\.available) { selectAction(first.id) }
                else if !profiles.contains(where:{$0.id == selectedProfileID}) { selectedProfileID = profiles.first?.id ?? "" }
            } catch { if selectionID == id, !Task.isCancelled { message = error.localizedDescription } }
            if selectionID == id { isInspecting = false }
        }
    }
    private func changeEngine(_ id: String, operation: @escaping @Sendable () async throws -> Void) {
        guard engineTask == nil else { return }
        engineBusyID = id; engineFailure = nil; engineProgress = .init(.installing)
        engineTask = Task {
            do {
                try await operation(); await refreshEngineLibrary()
                message = engineRefreshPending ? "Engine changes will activate when the current queue finishes. Existing jobs keep their pinned runtime." : "Engine library updated."
            } catch is CancellationError { message = "Installation cancelled. The previous active engine was kept." }
            catch { engineFailure = error.localizedDescription }
            engineBusyID = nil; engineProgress = nil; engineTask = nil
        }
    }
    func downloadEngine(_ entry: EngineDownload) {
        let model = self
        changeEngine(entry.id) {
            _ = try await EnginePacks.download(entry) { progress in Task { @MainActor in model.engineProgress = progress } }
        }
    }
    func cancelEngineInstall() { engineTask?.cancel() }
    func rollbackEngine(_ id: String) {
        guard !isProcessing else { return }
        changeEngine(id) { try await Task.detached { try EnginePacks.rollback(id) }.value }
    }
    func removeEngine(_ id: String) {
        guard !isProcessing else { return }
        changeEngine(id) { try await Task.detached { try EnginePacks.requestRemoval(id) }.value }
    }
}
@MainActor final class FolderGrants {
    static let shared = FolderGrants(); private var active: [URL] = []
    func restore() {
        let bookmarks = UserDefaults.standard.array(forKey:"outputBookmarks") as? [Data] ?? []; var refreshed: [Data] = []
        for data in bookmarks { var stale = false; guard let url = try? URL(resolvingBookmarkData:data,options:.withSecurityScope,relativeTo:nil,bookmarkDataIsStale:&stale) else { continue }; if url.startAccessingSecurityScopedResource() { active.append(url) }; refreshed.append(stale ? ((try? url.bookmarkData(options:.withSecurityScope,includingResourceValuesForKeys:nil,relativeTo:nil)) ?? data) : data) }
        UserDefaults.standard.set(refreshed,forKey:"outputBookmarks")
    }
    func save(_ url: URL) { guard !active.contains(url), let data = try? url.bookmarkData(options:.withSecurityScope,includingResourceValuesForKeys:nil,relativeTo:nil) else { return }; var saved = UserDefaults.standard.array(forKey:"outputBookmarks") as? [Data] ?? []; saved.append(data); UserDefaults.standard.set(saved,forKey:"outputBookmarks"); if url.startAccessingSecurityScopedResource() { active.append(url) } }
    func revokeAll() { releaseAll(); UserDefaults.standard.removeObject(forKey:"outputBookmarks") }
    func releaseAll() { active.forEach { $0.stopAccessingSecurityScopedResource() }; active = [] }
}
