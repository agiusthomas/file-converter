import Foundation
import Darwin

public enum InputSnapshot {
    public static func copy(_ source: URL, to destination: URL) throws {
        var before = stat()
        guard lstat(source.path,&before) == 0, (before.st_mode & S_IFMT) != S_IFLNK else { throw OperationFailure.invalidInput("An input is unavailable or is a symbolic link.") }
        if (before.st_mode & S_IFMT) == S_IFDIR {
            try FileManager.default.createDirectory(at:destination,withIntermediateDirectories:false)
            guard let enumerator = FileManager.default.enumerator(at:source,includingPropertiesForKeys:[.isDirectoryKey,.isSymbolicLinkKey]) else { throw OperationFailure.invalidInput("Cannot inspect input folder.") }
            var count = 0
            while let child = enumerator.nextObject() as? URL {
                try Task.checkCancellation(); count += 1; guard count <= 10000 else { throw OperationFailure.resourceLimit }
                var info = stat(); guard lstat(child.path,&info) == 0 else { throw OperationFailure.invalidInput("Input folder changed while copying.") }
                let path = destination.appendingPathComponent(try PathPolicy.relativePath(of:child,under:source))
                switch info.st_mode & S_IFMT {
                case S_IFDIR: try FileManager.default.createDirectory(at:path,withIntermediateDirectories:false)
                case S_IFREG: try copy(child,to:path)
                default: throw OperationFailure.unsupported("Links and special files cannot be included in a conversion snapshot.")
                }
            }
        } else {
            guard (before.st_mode & S_IFMT) == S_IFREG else { throw OperationFailure.invalidInput("Choose a regular file.") }
            if clonefile(source.path,destination.path,0) != 0 { try FileManager.default.copyItem(at:source,to:destination) }
        }
        var after = stat()
        guard lstat(source.path,&after) == 0, before.st_ino == after.st_ino, before.st_size == after.st_size, before.st_mtimespec.tv_sec == after.st_mtimespec.tv_sec, before.st_mtimespec.tv_nsec == after.st_mtimespec.tv_nsec else { throw OperationFailure.invalidInput("An input changed while its snapshot was being created. Wait for it to finish saving, then retry.") }
    }
}
