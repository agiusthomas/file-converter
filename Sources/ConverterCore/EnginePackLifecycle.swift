import Foundation
import Darwin

/// Lifetime pins belong to the app/CLI coordinator, not the read-only worker.
/// Stale pins retain code while their owner is alive; PID reuse only delays GC.
public final class EnginePackLease: @unchecked Sendable {
    struct Record: Codable { var pid: Int32; var bundles: [String] }
    private var files: [URL] = []
    public init(packs: [InstalledEnginePack]) throws {
        do {
            for (root,packs) in Dictionary(grouping:packs,by:{$0.location.deletingLastPathComponent()}) {
                try EnginePacks.withStoreLock(root) {
                    let leases = root.appendingPathComponent(".leases",isDirectory:true)
                    try FileManager.default.createDirectory(at:leases,withIntermediateDirectories:true)
                    let values = try leases.resourceValues(forKeys:[.isDirectoryKey,.isSymbolicLinkKey])
                    guard values.isDirectory == true, values.isSymbolicLink != true else { throw OperationFailure.verification("The runtime pin directory must not be a symbolic link.") }
                    let file = leases.appendingPathComponent(UUID().uuidString + ".json")
                    let record = Record(pid:getpid(),bundles:packs.map(\.location.lastPathComponent))
                    try JSONEncoder().encode(record).write(to:file,options:.atomic)
                    files.append(file)
                }
            }
        } catch { release(); throw error }
    }
    private func release() {
        for file in files { try? EnginePacks.withStoreLock(file.deletingLastPathComponent().deletingLastPathComponent()) { try FileManager.default.removeItem(at:file) } }
        files = []
    }
    deinit { release() }
}

extension EnginePacks {
    static func withStoreLock<T>(_ root: URL, _ body: () throws -> T) throws -> T {
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        let rootValues = try root.resourceValues(forKeys:[.isDirectoryKey,.isSymbolicLinkKey])
        guard rootValues.isDirectory == true, rootValues.isSymbolicLink != true else { throw OperationFailure.verification("The engine store must be a regular directory.") }
        let descriptor = open(root.appendingPathComponent(".store-lock").path,O_CREAT | O_RDWR | O_NOFOLLOW,0o600)
        guard descriptor >= 0 else { throw OperationFailure.process("Cannot lock the engine store.") }
        defer { close(descriptor) }
        guard flock(descriptor,LOCK_EX) == 0 else { throw OperationFailure.process("Cannot lock the engine store.") }
        defer { flock(descriptor,LOCK_UN) }
        return try body()
    }
    public static func pendingRemovals(root: URL = defaultRoot) -> Set<String> {
        Set(knownIDs.filter { FileManager.default.fileExists(atPath:root.appendingPathComponent($0 + ".remove").path) })
    }
    public static func requestRemoval(_ id: String, root: URL = defaultRoot) throws {
        guard knownIDs.contains(id) else { throw OperationFailure.invalidOptions("Unknown engine pack.") }
        try withStoreLock(root) {
            // Persist intent first. Startup can finish an interrupted removal.
            try Data("1".utf8).write(to:root.appendingPathComponent(id + ".remove"),options:.atomic)
            for suffix in ["current","previous"] {
                let pointer = root.appendingPathComponent(id + "." + suffix)
                if FileManager.default.fileExists(atPath:pointer.path) { try FileManager.default.removeItem(at:pointer) }
            }
        }
    }
    /// Returns IDs still waiting for a live snapshot. Unknown/corrupt lease
    /// records fail closed, so incomplete bookkeeping can never delete code.
    @discardableResult public static func collectRemovals(root: URL = defaultRoot) throws -> Set<String> {
        guard FileManager.default.fileExists(atPath:root.path) else { return [] }
        return try withStoreLock(root) {
            let pending = pendingRemovals(root:root)
            guard !pending.isEmpty else { return [] }
            var pinned = Set<String>()
            let leases = root.appendingPathComponent(".leases")
            if FileManager.default.fileExists(atPath:leases.path) {
                let directory = try leases.resourceValues(forKeys:[.isDirectoryKey,.isSymbolicLinkKey])
                guard directory.isDirectory == true, directory.isSymbolicLink != true else { return pending }
                for file in try FileManager.default.contentsOfDirectory(at:leases,includingPropertiesForKeys:nil) {
                    let values = try file.resourceValues(forKeys:[.isRegularFileKey,.isSymbolicLinkKey,.fileSizeKey])
                    guard values.isRegularFile == true, values.isSymbolicLink != true, (values.fileSize ?? Int.max) <= 65536,
                          file.lastPathComponent.range(of:#"^[0-9A-Fa-f-]{36}\.json$"#,options:.regularExpression) != nil else { return pending }
                    let pattern = "^(" + knownIDs.sorted().joined(separator:"|") + #")-[0-9]+(\.[0-9]+){1,3}\.bundle$"#
                    guard let record = try? JSONDecoder().decode(EnginePackLease.Record.self,from:Data(contentsOf:file)), record.pid > 0, !record.bundles.isEmpty,
                          record.bundles.allSatisfy({ $0.range(of:pattern,options:.regularExpression) != nil }) else { return pending }
                    if kill(record.pid,0) == 0 || errno == EPERM { pinned.formUnion(record.bundles) }
                    else { try FileManager.default.removeItem(at:file) }
                }
            }
            var waiting = Set<String>()
            for id in pending {
                // Complete pointer removal after a crash during requestRemoval.
                for suffix in ["current","previous"] {
                    let pointer = root.appendingPathComponent(id + "." + suffix)
                    if FileManager.default.fileExists(atPath:pointer.path) { try FileManager.default.removeItem(at:pointer) }
                }
                for file in try FileManager.default.contentsOfDirectory(at:root,includingPropertiesForKeys:[.isSymbolicLinkKey]) where file.lastPathComponent.range(of:"^" + id + #"-[0-9]+(\.[0-9]+){1,3}\.bundle$"#,options:.regularExpression) != nil {
                    if pinned.contains(file.lastPathComponent) { waiting.insert(id); continue }
                    guard try file.resourceValues(forKeys:[.isSymbolicLinkKey]).isSymbolicLink != true else { throw OperationFailure.verification("An engine removal path is a symbolic link.") }
                    try FileManager.default.removeItem(at:file)
                }
                if !waiting.contains(id) { try FileManager.default.removeItem(at:root.appendingPathComponent(id + ".remove")) }
            }
            return waiting
        }
    }
    public static func rollbackVersion(_ id: String, root: URL = defaultRoot) -> String? {
        guard knownIDs.contains(id), let name = try? String(contentsOf:root.appendingPathComponent(id + ".previous"),encoding:.utf8),
              name == URL(fileURLWithPath:name).lastPathComponent,
              let team = try? signingTeam(publisherCodeURL), let pack = try? verify(root.appendingPathComponent(name),trustedTeam:team) else { return nil }
        return pack.manifest.version
    }
}
