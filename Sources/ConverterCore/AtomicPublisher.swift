import Foundation
import Darwin

public enum AtomicPublisher {
    /// The stage and final file live on the same volume. RENAME_EXCL makes
    /// name allocation safe even when another conversion publishes concurrently.
    public static func publish(stagedFile: URL, source: URL, directory: URL, extension suffix: String) throws -> URL {
        let stem = source.deletingPathExtension().lastPathComponent
        for index in 1...10_000 {
            let name = index == 1 ? "\(stem).\(suffix)" : "\(stem) \(index).\(suffix)"
            let target = directory.appendingPathComponent(name)
            let result = stagedFile.withUnsafeFileSystemRepresentation { stagePath in
                target.withUnsafeFileSystemRepresentation { outputPath in
                    renamex_np(stagePath!, outputPath!, UInt32(RENAME_EXCL))
                }
            }
            if result == 0 { return target }
            let errorCode = errno
            if errorCode == EEXIST { continue }
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errorCode), userInfo: [NSLocalizedDescriptionKey: "Could not save the result in \(directory.lastPathComponent): \(String(cString: strerror(errorCode)))"])
        }
        throw CocoaError(.fileWriteFileExists)
    }
}
