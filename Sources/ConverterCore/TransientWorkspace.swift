import Foundation

public enum TransientWorkspace {
    public static var root: URL { FileManager.default.urls(for:.cachesDirectory,in:.userDomainMask)[0].appendingPathComponent("File Converter/Temporary",isDirectory:true) }
    /// Reserve an owned path. The caller creates it only once execution starts.
    public static func url(prefix: String) throws -> URL {
        guard prefix.range(of:#"^[a-z-]+$"#,options:.regularExpression) != nil else { throw OperationFailure.invalidOptions("Invalid temporary workspace name.") }
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
        return root.appendingPathComponent(prefix+"-"+UUID().uuidString,isDirectory:true)
    }
    /// Returned Shortcuts files remain available for seven days. Only our own
    /// UUID directories are eligible; links and recent work are never removed.
    public static func removeExpired(now: Date = Date()) throws {
        guard FileManager.default.fileExists(atPath:root.path) else { return }
        for child in try FileManager.default.contentsOfDirectory(at:root,includingPropertiesForKeys:[.creationDateKey,.isDirectoryKey,.isSymbolicLinkKey]) {
            guard child.lastPathComponent.range(of:#"^[a-z-]+-[0-9A-Fa-f-]{36}$"#,options:.regularExpression) != nil else { continue }
            let values = try child.resourceValues(forKeys:[.creationDateKey,.isDirectoryKey,.isSymbolicLinkKey])
            if values.isDirectory == true, values.isSymbolicLink != true, let date = values.creationDate, now.timeIntervalSince(date) > 7*24*3600 { try FileManager.default.removeItem(at:child) }
        }
    }
}
