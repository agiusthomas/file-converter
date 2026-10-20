import Foundation

public struct WatchRule: Codable, Identifiable, Sendable {
    public var id: UUID
    public var folder: URL
    public var bookmark: Data?
    public var recipe: Recipe
    public var extensions: [String]
    public var enabled: Bool
    public init(folder: URL, recipe: Recipe, extensions: [String], enabled: Bool = true) {
        self.id = UUID(); self.folder = folder; self.recipe = recipe; self.extensions = extensions.map { $0.lowercased() }; self.enabled = enabled
        bookmark = try? folder.bookmarkData(options:.withSecurityScope,includingResourceValuesForKeys:nil,relativeTo:nil)
    }
}
public struct FileObservation: Codable, Equatable, Sendable {
    public var size: Int64
    public var modified: Date
    public init(size: Int64, modified: Date) { self.size = size; self.modified = modified }
}
public struct StableFileTracker: Sendable {
    private var observed: [URL:(FileObservation,Date)] = [:]
    private var handled: [URL:FileObservation] = [:]
    public init() {}
    public mutating func baseline(_ files: [URL:FileObservation]) { observed = [:]; handled = files }
    public mutating func ready(_ files: [URL:FileObservation], now: Date, settle: TimeInterval = 4) -> [URL] {
        observed = observed.filter { files[$0.key] != nil }; handled = handled.filter { files[$0.key] != nil }
        var ready: [URL] = []
        for (url,value) in files {
            if handled[url] == value { continue }
            if let previous = observed[url], previous.0 == value, now.timeIntervalSince(previous.1) >= settle { ready.append(url); handled[url] = value; observed.removeValue(forKey:url) }
            else if observed[url]?.0 != value { observed[url] = (value,now) }
        }
        return ready.sorted { $0.path < $1.path }
    }
}
public actor WatchedFolderRunner {
    private let coordinator: JobCoordinator
    private var task: Task<Void,Never>?
    public init(coordinator: JobCoordinator) { self.coordinator = coordinator }
    public func stop() { task?.cancel(); task = nil }
    public func start(_ rules: [WatchRule], event: @escaping @Sendable (String) -> Void) {
        task?.cancel()
        task = Task {
            var trackers: [UUID:StableFileTracker] = [:]
            var grants: [URL] = []
            var resolved: [WatchRule] = []
            for var rule in rules where rule.enabled {
                if let bookmark = rule.bookmark { var stale = false; if let url = try? URL(resolvingBookmarkData:bookmark,options:.withSecurityScope,relativeTo:nil,bookmarkDataIsStale:&stale), !stale { rule.folder = url; if url.startAccessingSecurityScopedResource() { grants.append(url) } } }
                do { var tracker = StableFileTracker(); tracker.baseline(try self.files(rule)); trackers[rule.id] = tracker; resolved.append(rule) }
                catch { event("Watched folder \(rule.folder.lastPathComponent): \(error.localizedDescription)") }
            }
            defer { grants.forEach { $0.stopAccessingSecurityScopedResource() } }
            while !Task.isCancelled {
                do { try await Task.sleep(nanoseconds:2_000_000_000) } catch { return }
                for rule in resolved {
                    do {
                        let ready = trackers[rule.id]?.ready(try self.files(rule),now:Date()) ?? []
                        for file in ready {
                            try Task.checkCancellation()
                            let destination = rule.folder.appendingPathComponent("Converted",isDirectory:true)
                            try FileManager.default.createDirectory(at:destination,withIntermediateDirectories:true)
                            _ = try await coordinator.run(rule.recipe,inputs:[file],destination:destination)
                            event("Prepared \(file.lastPathComponent) in \(rule.folder.lastPathComponent)/Converted.")
                        }
                    } catch is CancellationError { return }
                    catch { event("Watched folder \(rule.folder.lastPathComponent): \(error.localizedDescription)") }
                }
            }
        }
    }
    private func files(_ rule: WatchRule) throws -> [URL:FileObservation] {
        let contents = try FileManager.default.contentsOfDirectory(at:rule.folder,includingPropertiesForKeys:[.isRegularFileKey,.isSymbolicLinkKey,.fileSizeKey,.contentModificationDateKey],options:[.skipsHiddenFiles,.skipsPackageDescendants])
        var result: [URL:FileObservation] = [:]
        for url in contents where rule.extensions.isEmpty || rule.extensions.contains(url.pathExtension.lowercased()) {
            let values = try url.resourceValues(forKeys:[.isRegularFileKey,.isSymbolicLinkKey,.fileSizeKey,.contentModificationDateKey])
            if values.isRegularFile == true && values.isSymbolicLink != true { result[url] = FileObservation(size:Int64(values.fileSize ?? 0),modified:values.contentModificationDate ?? .distantPast) }
        }
        return result
    }
}
