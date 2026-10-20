import Foundation

public struct EngineDownloadProgress: Sendable {
    public enum Phase: String, Sendable { case downloading, verifying, extracting, installing }
    public var phase: Phase
    public var receivedBytes: Int64
    public var totalBytes: Int64
    public init(_ phase: Phase, receivedBytes: Int64 = 0, totalBytes: Int64 = 0) { self.phase = phase; self.receivedBytes = receivedBytes; self.totalBytes = totalBytes }
}

/// Streams to disk and enforces the signed catalog's byte ceiling during receipt,
/// rather than discovering an oversized download only after disk exhaustion.
final class BoundedEngineDownload: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let entry: EngineDownload
    private let progress: @Sendable (EngineDownloadProgress) -> Void
    private let lock = NSLock()
    private var continuation: CheckedContinuation<URL,Error>?
    private var session: URLSession?
    private var task: URLSessionDownloadTask?
    private var cancelled = false
    private var completed = false
    private var lastProgress = Date.distantPast
    init(entry: EngineDownload, progress: @escaping @Sendable (EngineDownloadProgress) -> Void) { self.entry = entry; self.progress = progress }
    func run() async throws -> URL {
        try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { continuation in
                lock.lock(); self.continuation = continuation
                if cancelled { lock.unlock(); finish(.failure(CancellationError())); return }
                let configuration = URLSessionConfiguration.ephemeral
                configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
                configuration.timeoutIntervalForRequest = 30
                configuration.timeoutIntervalForResource = 3600
                let session = URLSession(configuration:configuration,delegate:self,delegateQueue:nil)
                self.session = session
                let task = session.downloadTask(with:entry.url); self.task = task
                lock.unlock(); task.resume()
            }
        },onCancel:{
            self.lock.lock(); self.cancelled = true; let task = self.task; self.lock.unlock()
            task?.cancel()
        })
    }
    private func finish(_ result: Result<URL,Error>) {
        lock.lock(); guard !completed else { lock.unlock(); return }; completed = true
        let continuation = continuation, session = session
        self.continuation = nil; self.session = nil; self.task = nil; lock.unlock()
        continuation?.resume(with:result); session?.invalidateAndCancel()
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(request.url?.scheme == "https" ? request : nil)
    }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard totalBytesWritten <= entry.downloadBytes, totalBytesExpectedToWrite <= entry.downloadBytes else { finish(.failure(OperationFailure.resourceLimit)); return }
        if Date().timeIntervalSince(lastProgress) >= 0.1 || totalBytesWritten == entry.downloadBytes {
            lastProgress = Date(); progress(.init(.downloading,receivedBytes:totalBytesWritten,totalBytes:entry.downloadBytes))
        }
    }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        lock.lock(); let completed = completed; lock.unlock()
        guard !completed else { return }
        do {
            guard let response = downloadTask.response as? HTTPURLResponse, response.statusCode == 200, response.url?.scheme == "https",
                  Int64(try location.resourceValues(forKeys:[.fileSizeKey]).fileSize ?? 0) == entry.downloadBytes else { throw OperationFailure.verification("The engine download is incomplete or has an unexpected size.") }
            let target = FileManager.default.temporaryDirectory.appendingPathComponent("engine-download-\(UUID().uuidString).zip")
            try FileManager.default.moveItem(at:location,to:target)
            finish(.success(target))
        } catch { finish(.failure(error)) }
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error {
            lock.lock(); let cancelled = cancelled; lock.unlock()
            finish(.failure(cancelled ? CancellationError() : error))
        }
    }
}

extension EnginePacks {
    public static func catalog() throws -> [EngineDownload] {
        guard let url = Bundle.main.url(forResource:"EngineCatalog",withExtension:"json") else { return [] }
        let entries = try JSONDecoder().decode([EngineDownload].self,from:Data(contentsOf:url))
        guard entries.allSatisfy(validDownload), Set(entries.map { $0.id + "/" + $0.version }).count == entries.count else { throw OperationFailure.verification("The bundled engine catalog is invalid.") }
        return entries
    }
    public static func validDownload(_ entry: EngineDownload) -> Bool {
        knownIDs.contains(entry.id) && entry.version.range(of:#"^[0-9]+(\.[0-9]+){1,3}$"#,options:.regularExpression) != nil &&
        entry.url.scheme == "https" && entry.url.host != nil && entry.url.user == nil && entry.url.password == nil &&
        entry.sha256.range(of:#"^[a-f0-9]{64}$"#,options:.regularExpression) != nil && entry.downloadBytes > 0 && entry.downloadBytes <= 4*1024*1024*1024 &&
        (entry.installedBytes.map { $0 > 0 && $0 <= 16*1024*1024*1024 } ?? true) &&
        (entry.publisherTeam.map { $0.range(of:#"^[A-Z0-9]{10}$"#,options:.regularExpression) != nil } ?? true)
    }
    public static func incompatibility(_ entry: EngineDownload) -> String? {
        if let minimum = entry.minimumAppVersion, minimum.compare(appVersion,options:.numeric) == .orderedDescending { return "Requires Glacier File Converter \(minimum) or later." }
        let version = ProcessInfo.processInfo.operatingSystemVersion
        let os = "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
        if let minimum = entry.minimumOSVersion, minimum.compare(os,options:.numeric) == .orderedDescending { return "Requires macOS \(minimum) or later." }
        #if arch(arm64)
        let architecture = "arm64"
        #else
        let architecture = "x86_64"
        #endif
        if let architectures = entry.architectures, !architectures.contains(architecture) { return "This runtime is incompatible with this Mac's architecture." }
        if let team = entry.publisherTeam, (try? signingTeam(publisherCodeURL)) != team { return "Requires a Developer ID signed Glacier File Converter build from this engine's publisher." }
        return nil
    }
}
