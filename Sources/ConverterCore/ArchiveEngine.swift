import Foundation
import ArchiveBridge

public enum ArchiveEngine {
    public static var available: Bool { fc_archive_available() != 0 }
    public static var version: String { String(cString: fc_archive_version()) }
    public struct Member: Sendable { public var name: String; public var size: Int64; public var directory: Bool }
    public static func safeName(_ name: String) throws -> String {
        let name = name.precomposedStringWithCanonicalMapping
        let components = name.split(separator: "/", omittingEmptySubsequences: false)
        guard !name.isEmpty, name.utf8.count <= 4096, !name.hasPrefix("/"), !name.contains("\\"), !name.contains(":"), !name.contains("\0"),
              !components.dropLast().contains(""), !components.contains(".."), !components.contains("."), !name.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { throw OperationFailure.invalidInput("Unsafe archive path: \(name.prefix(100))") }
        return name
    }
    public static func list(_ url: URL) throws -> [Member] {
        guard let reader = fc_archive_open(url.path) else { throw OperationFailure.invalidInput("The archive cannot be opened or is encrypted.") }
        defer { fc_archive_close(reader) }
        var result: [Member] = []; var total: Int64 = 0; var seen = Set<String>()
        let inputBytes = Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        while true {
            try Task.checkCancellation()
            let status = fc_archive_next(reader)
            if status == 1 { break }
            guard status == 0, let raw = fc_archive_name(reader), let name = String(validatingUTF8: raw) else { throw OperationFailure.invalidInput("An archive member could not be read.") }
            let safe = try safeName(name)
            guard fc_archive_kind(reader) != 0 else { throw OperationFailure.unsupported("Archives containing links or special files are not supported.") }
            let size = fc_archive_size(reader)
            guard size >= 0, size <= 8 * 1024 * 1024 * 1024, total <= 16 * 1024 * 1024 * 1024 - size, result.count < 10000 else { throw OperationFailure.resourceLimit }
            let key = safe.trimmingCharacters(in: CharacterSet(charactersIn: "/")).lowercased()
            guard seen.insert(key).inserted else { throw OperationFailure.invalidInput("Archive contains duplicate or case-conflicting paths.") }
            total += size
            guard total <= max(512 * 1024 * 1024, inputBytes > Int64.max / 1000 ? Int64.max : inputBytes * 1000) else { throw OperationFailure.resourceLimit }
            result.append(Member(name: safe, size: size, directory: fc_archive_kind(reader) == 2))
        }
        return result
    }
    public static func readMember(_ name: String, from url: URL, limit: Int = 65536) throws -> Data {
        _ = try safeName(name)
        guard limit > 0, limit <= 32*1024*1024, let reader = fc_archive_open(url.path) else { throw OperationFailure.invalidInput("Cannot read archive metadata.") }
        defer { fc_archive_close(reader) }
        var count = 0
        while true {
            try Task.checkCancellation(); count += 1; guard count <= 10000 else { throw OperationFailure.resourceLimit }
            let status = fc_archive_next(reader)
            if status == 1 { throw OperationFailure.invalidInput("Required package metadata is missing.") }
            guard status == 0, let raw = fc_archive_name(reader), let member = String(validatingUTF8:raw) else { throw OperationFailure.invalidInput("Cannot read archive metadata.") }
            if member != name { continue }
            guard fc_archive_kind(reader) == 1, fc_archive_size(reader) >= 0, fc_archive_size(reader) <= Int64(limit) else { throw OperationFailure.resourceLimit }
            var result = Data(), buffer = [UInt8](repeating:0,count:min(limit,65536))
            while true {
                try Task.checkCancellation()
                let bytes = fc_archive_read(reader,&buffer,buffer.count)
                guard bytes >= 0, result.count <= limit-bytes else { throw OperationFailure.resourceLimit }
                if bytes == 0 { break }; result.append(contentsOf:buffer.prefix(bytes))
            }
            guard Int64(result.count) == fc_archive_size(reader) else { throw OperationFailure.verification("Package metadata size changed.") }; return result
        }
    }
    public static func extract(_ url: URL, to directory: URL, selected: [String] = []) throws -> [URL] {
        let members = try list(url)
        let names = Set(members.map(\.name))
        guard selected.allSatisfy(names.contains) else { throw OperationFailure.invalidOptions("A selected archive member is missing.") }
        guard let reader = fc_archive_open(url.path) else { throw OperationFailure.invalidInput("Cannot open archive.") }
        defer { fc_archive_close(reader) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        var outputs: [URL] = []; var buffer = [UInt8](repeating: 0, count: 65536); var expanded: Int64 = 0
        for member in members {
            try Task.checkCancellation()
            guard fc_archive_next(reader) == 0 else { throw OperationFailure.verification("Archive changed while extracting.") }
            let chosen = selected.isEmpty || selected.contains(member.name) || selected.contains(where: { member.name.hasPrefix($0.hasSuffix("/") ? $0 : $0 + "/") })
            if !chosen { continue }
            let target = directory.appendingPathComponent(member.name)
            guard target.standardizedFileURL.path.hasPrefix(directory.standardizedFileURL.path + "/") else { throw OperationFailure.invalidInput("Archive path escapes its destination.") }
            if member.directory { try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true); continue }
            try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            let fd = open(target.path,O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW,0o600)
            guard fd >= 0 else { throw OperationFailure.process("Cannot create archive output without replacing another member.") }
            let handle = FileHandle(fileDescriptor:fd,closeOnDealloc:true)
            do {
                var bytes: Int64 = 0
                while true {
                    try Task.checkCancellation()
                    let count = fc_archive_read(reader, &buffer, buffer.count)
                    guard count >= 0 else { throw OperationFailure.invalidInput("Archive member failed its integrity check.") }
                    if count == 0 { break }
                    bytes += Int64(count); expanded += Int64(count)
                    guard bytes <= member.size, expanded <= 16 * 1024 * 1024 * 1024 else { throw OperationFailure.resourceLimit }
                    try handle.write(contentsOf: Data(buffer.prefix(count)))
                }
                guard bytes == member.size else { throw OperationFailure.verification("Archive member size mismatch.") }
                try handle.close()
            } catch { try? handle.close(); throw error }
            outputs.append(target)
        }
        return outputs
    }
    public static func create(_ inputs: [URL], to output: URL, format: String) throws {
        guard ["zip", "tar", "tar.gz", "7z"].contains(format) else { throw OperationFailure.unsupported("Unsupported archive output.") }
        var paths: [String] = [], names: [String] = []; var seen = Set<String>(); var total: Int64 = 0
        func append(_ url: URL, name: String) throws {
            _ = try safeName(name)
            let values = try url.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey, .isRegularFileKey, .fileSizeKey])
            guard values.isSymbolicLink != true, values.isRegularFile == true || values.isDirectory == true else { throw OperationFailure.unsupported("Links and special files cannot be archived.") }
            guard seen.insert(name.lowercased()).inserted else { throw OperationFailure.invalidInput("Archive input names conflict. Rename the files first.") }
            total += Int64(values.fileSize ?? 0)
            guard paths.count < 10000, total <= 16 * 1024 * 1024 * 1024 else { throw OperationFailure.resourceLimit }
            paths.append(url.path); names.append(name)
        }
        for input in inputs {
            try append(input, name: input.lastPathComponent)
            if (try input.resourceValues(forKeys: [.isDirectoryKey])).isDirectory == true {
                guard let iterator = FileManager.default.enumerator(at: input, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey]) else { throw OperationFailure.invalidInput("Cannot read folder.") }
                for case let child as URL in iterator { try Task.checkCancellation(); try append(child, name: input.lastPathComponent + "/" + PathPolicy.relativePath(of:child,under:input)) }
            }
        }
        let cPaths = paths.map { strdup($0) }; let cNames = names.map { strdup($0) }
        defer { cPaths.forEach { free($0) }; cNames.forEach { free($0) } }
        let pathPointers = cPaths.map { UnsafePointer<CChar>($0) }; let namePointers = cNames.map { UnsafePointer<CChar>($0) }
        var error = [CChar](repeating: 0, count: 1024)
        let status = fc_archive_create(output.path, format, pathPointers, namePointers, paths.count, &error, error.count)
        guard status == 0 else { throw OperationFailure.process(String(cString: error)) }
        let actual = try list(output)
        guard actual.count == names.count else { throw OperationFailure.verification("Archive member count does not match its inputs.") }
    }
}
