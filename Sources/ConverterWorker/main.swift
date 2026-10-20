import Foundation
import ConverterCore

if CommandLine.arguments.contains("--xpc") || Bundle.main.bundleURL.pathExtension == "xpc" {
    let delegate = WorkerDelegate(); let listener = NSXPCListener.service(); listener.delegate = delegate
    withExtendedLifetime(delegate) { listener.resume() }
} else {
    let input = FileHandle.standardInput.readDataToEndOfFile()
    guard input.count <= 16 * 1024 * 1024 else { exit(2) }
    Task {
        let response: WorkerResponse
        do {
            let envelope = try JSONDecoder().decode(WorkerEnvelope.self,from:input)
            response = try await WorkerExecutor.perform(envelope)
        } catch { response = WorkerResponse(error:error.localizedDescription) }
        do { FileHandle.standardOutput.write(try JSONEncoder().encode(response)); exit(response.error == nil ? 0 : 1) }
        catch { exit(2) }
    }
    RunLoop.main.run()
}
