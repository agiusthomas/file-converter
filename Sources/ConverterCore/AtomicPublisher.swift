import Foundation
import Darwin

public enum AtomicPublisher {
    public static func publish(stagedItem: URL, directory: URL, preferredName: String) throws -> URL {
        guard preferredName == URL(fileURLWithPath:preferredName).lastPathComponent, !preferredName.isEmpty, preferredName != ".", preferredName != ".." else { throw OperationFailure.invalidOptions("Invalid output filename.") }
        let ext = (preferredName as NSString).pathExtension
        let stem = ext.isEmpty ? preferredName : (preferredName as NSString).deletingPathExtension
        for index in 1...10000 {
            let name = index == 1 ? preferredName : stem + " \(index)" + (ext.isEmpty ? "" : "." + ext)
            let target = directory.appendingPathComponent(name)
            let status = stagedItem.withUnsafeFileSystemRepresentation { from in target.withUnsafeFileSystemRepresentation { to in renamex_np(from!,to!,UInt32(RENAME_EXCL)) } }
            if status == 0 { return target }
            if errno == EEXIST { continue }
            throw NSError(domain:NSPOSIXErrorDomain,code:Int(errno),userInfo:[NSLocalizedDescriptionKey:"Could not publish \(name): \(String(cString:strerror(errno)))"])
        }
        throw CocoaError(.fileWriteFileExists)
    }
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
