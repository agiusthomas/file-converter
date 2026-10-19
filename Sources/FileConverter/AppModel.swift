import AppKit
import Combine
import ConverterCore
import UniformTypeIdentifiers

enum WorkspacePage: String, CaseIterable { case convert = "Convert", activity = "Activity", settings = "Settings" }

struct ConversionJob: Identifiable {
    enum State { case queued, running, succeeded, failed, cancelled }
    let id = UUID()
    let source: URL
    let format: ImageFormat
    let options: ConversionOptions
    var state: State = .queued
    var output: URL?
    var detail: String = "Waiting to convert"
    var notices: [String] = []
}

@MainActor final class AppModel: ObservableObject {
    let registry = CapabilityRegistry()
    private let converter = ImageConverter()
    private var queueTask: Task<Void, Never>?
    @Published var page: WorkspacePage = .convert
    @Published var sources: [URL] = []
    @Published var selectedFormat: ImageFormat = .jpeg
    @Published var jobs: [ConversionJob] = []
    @Published var isProcessing = false
    @Published var isCancelling = false
    @Published var message: String?
    @Published var wheelEnabled: Bool {
        didSet { UserDefaults.standard.set(wheelEnabled, forKey: "wheelEnabled"); onWheelSettingChanged?(wheelEnabled) }
    }
    @Published var quality: Double {
        didSet { UserDefaults.standard.set(quality, forKey: "quality") }
    }
    @Published var preserveMetadata: Bool {
        didSet { UserDefaults.standard.set(preserveMetadata, forKey: "preserveMetadata") }
    }
    var onWheelSettingChanged: ((Bool) -> Void)?
    var onShowWheel: (([URL]) -> Void)?
    var onShowWindow: (() -> Void)?
    var formats: [ImageFormat] { registry.destinations(for: sources) }
    var completedCount: Int { jobs.filter { $0.state == .succeeded }.count }
    var failedCount: Int { jobs.filter { $0.state == .failed }.count }
    var activeCount: Int { jobs.filter { [.queued, .running].contains($0.state) }.count }
    var progress: Double {
        guard !jobs.isEmpty else { return 0 }
        return Double(jobs.filter { ![.queued, .running].contains($0.state) }.count) / Double(jobs.count)
    }

    init() {
        UserDefaults.standard.register(defaults: ["wheelEnabled": true, "quality": 0.9, "preserveMetadata": true])
        wheelEnabled = UserDefaults.standard.bool(forKey: "wheelEnabled")
        quality = UserDefaults.standard.double(forKey: "quality")
        preserveMetadata = UserDefaults.standard.bool(forKey: "preserveMetadata")
    }
    func setSources(_ urls: [URL]) {
        let unique = Array(NSOrderedSet(array: urls).array as? [URL] ?? urls)
        guard !unique.isEmpty, unique.allSatisfy(registry.accepts) else {
            message = "Choose image files. PDF input and other file families are coming in later builds."
            return
        }
        sources = unique
        if !formats.contains(selectedFormat), let first = formats.first { selectedFormat = first }
        message = formats.isEmpty ? "These images have no shared output format in this build." : nil
        page = .convert
    }
    func pickFiles(showWheel: Bool = false) {
        let panel = NSOpenPanel()
        panel.title = showWheel ? "Choose images for the conversion wheel" : "Choose images to convert"
        panel.prompt = "Choose images"
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK else { return }
        setSources(panel.urls)
        if showWheel, !formats.isEmpty { onShowWheel?(sources) }
    }
    func convertSelection() { enqueue(sources, to: selectedFormat) }
    func enqueue(_ urls: [URL], to format: ImageFormat) {
        guard !isCancelling, registry.destinations(for: urls).contains(format) else { return }
        let options = ConversionOptions(quality: quality, preserveMetadata: preserveMetadata)
        jobs += urls.map { ConversionJob(source: $0, format: format, options: options) }
        message = nil
        onShowWindow?()
        startQueue()
    }
    private func startQueue() {
        guard queueTask == nil else { return }
        isProcessing = true
        queueTask = Task { [weak self] in
            guard let self else { return }
            while let index = self.jobs.firstIndex(where: { $0.state == .queued }), !Task.isCancelled {
                let job = self.jobs[index]
                self.jobs[index].state = .running
                self.jobs[index].detail = "Converting and verifying…"
                do {
                    let result = try await self.converter.convert(.init(source: job.source, format: job.format, options: job.options))
                    self.jobs[index].state = .succeeded
                    self.jobs[index].output = result.output
                    self.jobs[index].notices = result.notices
                    self.jobs[index].detail = "\(result.width) × \(result.height) · \(ByteCountFormatter.string(fromByteCount: result.byteCount, countStyle: .file))"
                } catch is CancellationError {
                    self.jobs[index].state = .cancelled
                    self.jobs[index].detail = "Cancelled · original unchanged"
                } catch {
                    self.jobs[index].state = .failed
                    self.jobs[index].detail = error.localizedDescription
                }
            }
            if Task.isCancelled {
                for index in self.jobs.indices where self.jobs[index].state == .queued {
                    self.jobs[index].state = .cancelled; self.jobs[index].detail = "Cancelled"
                }
            }
            self.isProcessing = false; self.isCancelling = false; self.queueTask = nil
        }
    }
    func cancel() { isCancelling = true; queueTask?.cancel() }
    func clearFinished() { jobs.removeAll { ![.queued, .running].contains($0.state) } }
    func reveal(_ url: URL) { NSWorkspace.shared.activateFileViewerSelecting([url]) }
    func revealAll() {
        let outputs = jobs.compactMap(\.output)
        if !outputs.isEmpty { NSWorkspace.shared.activateFileViewerSelecting(outputs) }
    }
    func allowOutputFolder() {
        let panel = NSOpenPanel()
        panel.title = "Allow an output folder"
        panel.message = "Choose the folder containing your images so converted files can be saved beside them."
        panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.canCreateDirectories = false
        panel.prompt = "Allow folder"
        guard panel.runModal() == .OK, let folder = panel.url else { return }
        do {
            let bookmark = try folder.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
            var bookmarks = UserDefaults.standard.array(forKey: "outputBookmarks") as? [Data] ?? []
            bookmarks.append(bookmark); UserDefaults.standard.set(bookmarks, forKey: "outputBookmarks")
            FolderGrants.shared.activate(bookmark)
            message = "Access allowed for \(folder.lastPathComponent). Failed conversions can now be added again."
        } catch { message = "Folder access could not be saved: \(error.localizedDescription)" }
    }
}

@MainActor final class FolderGrants {
    static let shared = FolderGrants()
    private var activeURLs: [URL] = []
    func restore() {
        for data in UserDefaults.standard.array(forKey: "outputBookmarks") as? [Data] ?? [] { activate(data) }
    }
    func activate(_ data: Data) {
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &stale), !stale else { return }
        if url.startAccessingSecurityScopedResource() { activeURLs.append(url) }
    }
    func releaseAll() { activeURLs.forEach { $0.stopAccessingSecurityScopedResource() }; activeURLs.removeAll() }
}
