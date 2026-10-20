@preconcurrency import Foundation

@objc public protocol ConversionWorkerProtocol {
    func perform(_ request: Data, reply: @escaping (Data?,String?) -> Void)
    func cancel(_ id: String)
}
public struct WorkerEnvelope: Codable, Sendable {
    public var schemaVersion = 1
    public var id: UUID
    public var inputs: [URL]
    public var request: OperationRequest?
    public var directory: URL?
    public var bookmarks: [Data]
    public var packs: [InstalledEnginePack]
    public init(inputs: [URL], request: OperationRequest? = nil, directory: URL? = nil, packs: [InstalledEnginePack] = []) {
        self.id = request?.id ?? UUID(); self.inputs = inputs; self.request = request; self.directory = directory; self.packs = packs
        // Cross-process bookmarks use implicit security scope. Persistent app-scoped
        // bookmarks cannot grant access to a differently identified XPC service.
        bookmarks = (inputs + (directory.map { [$0] } ?? []) + packs.map(\.location)).compactMap { try? $0.bookmarkData(options:[],includingResourceValuesForKeys:nil,relativeTo:nil) }
    }
}
public struct WorkerResponse: Codable, Sendable {
    public var assets: [AssetDescriptor]?; public var manifest: OutputManifest?; public var error: String?
    public init(assets: [AssetDescriptor]? = nil, manifest: OutputManifest? = nil, error: String? = nil) { self.assets = assets; self.manifest = manifest; self.error = error }
}
public protocol WorkerTransport: Sendable {
    func perform(_ envelope: WorkerEnvelope) async throws -> WorkerResponse
}
public final class XPCWorkerTransport: WorkerTransport, @unchecked Sendable {
    private let serviceName: String
    public init(serviceName: String? = nil) {
        self.serviceName = serviceName ?? (Bundle.main.object(forInfoDictionaryKey:"ConversionWorkerServiceName") as? String) ?? "io.local.file-converter.worker.development"
    }
    public func perform(_ envelope: WorkerEnvelope) async throws -> WorkerResponse {
        let handle = XPCConnectionHandle(serviceName:serviceName)
        handle.connection.remoteObjectInterface = NSXPCInterface(with:ConversionWorkerProtocol.self)
        let completion = XPCCompletion()
        // Sandbox/container initialization can wait on a macOS permission prompt
        // before the worker reaches main. Never leave inspection spinning forever.
        let timeout: UInt64 = envelope.request == nil ? 60 : 21600
        let watchdog = Task {
            do { try await Task.sleep(nanoseconds:timeout * 1_000_000_000) }
            catch { return }
            completion.finish(.failure(OperationFailure.process("The conversion worker did not respond in time. Check for macOS permission prompts, then try again.")))
            handle.connection.invalidate()
        }
        defer { watchdog.cancel() }
        return try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { continuation in
                guard completion.install(continuation) else { return }
                handle.connection.interruptionHandler = { completion.finish(.failure(OperationFailure.process("The conversion worker stopped. Retry the interrupted job."))) }
                handle.connection.invalidationHandler = { completion.finish(.failure(OperationFailure.process("The conversion worker disconnected."))) }
                handle.connection.resume()
                guard let proxy = handle.connection.remoteObjectProxyWithErrorHandler({ completion.finish(.failure($0)) }) as? ConversionWorkerProtocol else { completion.finish(.failure(OperationFailure.process("Cannot connect to the conversion worker."))); return }
                do {
                    let data = try JSONEncoder().encode(envelope)
                    proxy.perform(data) { data,error in
                        defer { handle.connection.invalidate() }
                        if let error { completion.finish(.failure(OperationFailure.process(error))); return }
                        guard let data else { completion.finish(.failure(OperationFailure.process("The worker returned no result."))); return }
                        do { completion.finish(.success(try JSONDecoder().decode(WorkerResponse.self,from:data))) } catch { completion.finish(.failure(error)) }
                    }
                } catch { handle.connection.invalidate(); completion.finish(.failure(error)) }
            }
        },onCancel: {
            // Each connection owns its service tasks; invalidation cancels all of
            // them, including when cancellation races initial connection setup.
            completion.finish(.failure(CancellationError())); handle.connection.invalidate()
        })
    }
}
// NSXPCConnection supports cross-thread invalidation. Keep its reference immutable
// while bridging callback completion and task cancellation.
private final class XPCConnectionHandle: @unchecked Sendable {
    let connection: NSXPCConnection
    init(serviceName: String) { connection = NSXPCConnection(serviceName:serviceName) }
}
private final class XPCCompletion: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<WorkerResponse,Error>?
    private var result: Result<WorkerResponse,Error>?
    func install(_ continuation: CheckedContinuation<WorkerResponse,Error>) -> Bool {
        lock.lock(); if let result { lock.unlock(); continuation.resume(with:result); return false } else { self.continuation = continuation; lock.unlock(); return true }
    }
    func finish(_ result: Result<WorkerResponse,Error>) {
        lock.lock(); guard self.result == nil else { lock.unlock(); return }; self.result = result
        let continuation = self.continuation; self.continuation = nil; lock.unlock(); continuation?.resume(with:result)
    }
}
public struct ProcessWorkerTransport: WorkerTransport {
    public var executable: URL
    public init(executable: URL) { self.executable = executable }
    public func perform(_ envelope: WorkerEnvelope) async throws -> WorkerResponse {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("converter-ipc-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:false)
        defer { try? FileManager.default.removeItem(at:directory) }
        let request = directory.appendingPathComponent("request.json"), result = directory.appendingPathComponent("result.json"), errors = directory.appendingPathComponent("errors.log")
        try JSONEncoder().encode(envelope).write(to:request)
        FileManager.default.createFile(atPath:result.path,contents:nil); FileManager.default.createFile(atPath:errors.path,contents:nil)
        let input = try FileHandle(forReadingFrom:request), output = try FileHandle(forWritingTo:result), errorLog = try FileHandle(forWritingTo:errors)
        defer { try? input.close(); try? output.close(); try? errorLog.close() }
        let process = Process(); process.executableURL = executable; process.standardInput = input; process.standardOutput = output; process.standardError = errorLog
        try process.run(); let start = Date()
        do {
            while process.isRunning {
                try Task.checkCancellation()
                guard Date().timeIntervalSince(start) < 21600, (try result.resourceValues(forKeys:[.fileSizeKey]).fileSize ?? 0) <= 16 * 1024 * 1024, (try errors.resourceValues(forKeys:[.fileSizeKey]).fileSize ?? 0) <= 8 * 1024 * 1024 else { throw OperationFailure.resourceLimit }
                try await Task.sleep(nanoseconds:30_000_000)
            }
            let data = try Data(contentsOf:result)
            if let response = try? JSONDecoder().decode(WorkerResponse.self,from:data), process.terminationStatus == 0 || response.error != nil { return response }
            throw OperationFailure.process("Conversion worker exited unexpectedly: " + String(decoding:(try Data(contentsOf:errors)).suffix(2000),as:UTF8.self))
        } catch { if process.isRunning { process.terminate(); try? await Task.sleep(nanoseconds:100_000_000); if process.isRunning { kill(process.processIdentifier,SIGKILL) }; process.waitUntilExit() }; throw error }
    }
}
public struct InProcessWorkerTransport: WorkerTransport {
    public init() {}
    public func perform(_ envelope: WorkerEnvelope) async throws -> WorkerResponse { try await WorkerExecutor.perform(envelope) }
}
public enum WorkerExecutor {
    public static func perform(_ envelope: WorkerEnvelope) async throws -> WorkerResponse {
        guard envelope.schemaVersion == 1, envelope.inputs.count <= 1000 else { throw OperationFailure.invalidInput("Unsupported worker request.") }
        var grants: [URL] = []
        for data in envelope.bookmarks {
            var stale = false
            if let url = try? URL(resolvingBookmarkData:data,options:.withoutUI,relativeTo:nil,bookmarkDataIsStale:&stale), !stale { _ = url.startAccessingSecurityScopedResource(); grants.append(url) }
        }
        defer { grants.forEach { $0.stopAccessingSecurityScopedResource() } }
        var packs: [InstalledEnginePack] = []
        if !envelope.packs.isEmpty {
            let team = try EnginePacks.signingTeam(EnginePacks.publisherCodeURL)
            packs = try envelope.packs.map { try EnginePacks.verify($0.location,trustedTeam:team) }
        }
        let engine = NativeEngine(packs:packs)
        if let request = envelope.request, let directory = envelope.directory {
            return WorkerResponse(manifest:try await engine.execute(request,in:directory))
        }
        return WorkerResponse(assets:try await engine.inspect(envelope.inputs))
    }
}
