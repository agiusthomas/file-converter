import Foundation
import ConverterCore

final class WorkerService: NSObject, ConversionWorkerProtocol, @unchecked Sendable {
    private let lock = NSLock()
    private var invalidated = false
    private var tasks: [String:Task<Void,Never>] = [:]
    func perform(_ data: Data, reply: @escaping (Data?,String?) -> Void) {
        guard data.count <= 16 * 1024 * 1024, let envelope = try? JSONDecoder().decode(WorkerEnvelope.self,from:data) else { reply(nil,"Malformed worker request."); return }
        lock.lock()
        guard !invalidated, tasks[envelope.id.uuidString] == nil else { lock.unlock(); reply(nil,"The worker connection is closed or the job already exists."); return }
        let task = Task { [weak self] in
            do { let result = try await WorkerExecutor.perform(envelope); reply(try JSONEncoder().encode(result),nil) }
            catch { reply(nil,error.localizedDescription) }
            self?.remove(envelope.id.uuidString)
        }
        tasks[envelope.id.uuidString] = task
        lock.unlock()
    }
    private func remove(_ id: String) { lock.lock(); tasks.removeValue(forKey:id); lock.unlock() }
    func cancel(_ id: String) { lock.lock(); let task = tasks[id]; lock.unlock(); task?.cancel() }
    func cancelAll() { lock.lock(); invalidated = true; let active = Array(tasks.values); lock.unlock(); active.forEach { $0.cancel() } }
}
final class WorkerDelegate: NSObject, NSXPCListenerDelegate {
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        let service = WorkerService()
        connection.invalidationHandler = { service.cancelAll() }
        connection.interruptionHandler = { service.cancelAll() }
        connection.exportedInterface = NSXPCInterface(with:ConversionWorkerProtocol.self)
        connection.exportedObject = service; connection.resume(); return true
    }
}
