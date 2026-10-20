import Foundation
import Security
import CryptoKit

public enum FileDigest {
    public static func sha256(_ url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom:url); defer { try? handle.close() }
        var digest = SHA256()
        while let data = try handle.read(upToCount:1024 * 1024), !data.isEmpty { try Task.checkCancellation(); digest.update(data:data) }
        return digest.finalize().map { String(format:"%02x",$0) }.joined()
    }
}
public struct EnginePackManifest: Codable, Sendable {
    public var schemaVersion: Int
    public var id: String
    public var version: String
    public var minimumAppVersion: String
    public var minimumOSVersion: String
    public var architectures: [String]
    public var tools: [String:String]
    public var files: [String:String]
    public var licenses: [String]
    public var installedBytes: Int64
    public var engineVersions: [String:String]
    public var models: [String:String]?
}
public struct InstalledEnginePack: Codable, Sendable, Identifiable {
    public var id: String { manifest.id }
    public var location: URL
    public var manifest: EnginePackManifest
}
public struct EngineDownload: Codable, Sendable {
    public var id: String
    public var version: String
    public var url: URL
    public var sha256: String
    public var downloadBytes: Int64
}
public enum EnginePacks {
    public static let appVersion = "0.2.0"
    public static let knownIDs: Set<String> = ["media","documents","ebooks","transcription","webp","pdf"]
    public static var defaultRoot: URL {
        if let path = ProcessInfo.processInfo.environment["FILE_CONVERTER_ENGINE_DIRECTORY"] { return URL(fileURLWithPath:path,isDirectory:true) }
        return FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("File Converter/Engines",isDirectory:true)
    }
    public static var publisherCodeURL: URL {
        let bundle = Bundle.main.bundleURL
        if ["app","xpc","bundle"].contains(bundle.pathExtension) { return bundle }
        return Bundle.main.executableURL ?? URL(fileURLWithPath:CommandLine.arguments[0])
    }
    public static func signingTeam(_ url: URL) throws -> String {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL,SecCSFlags(rawValue:0),&code) == errSecSuccess, let code,
              SecStaticCodeCheckValidity(code,SecCSFlags(rawValue:kSecCSStrictValidate),nil) == errSecSuccess else { throw OperationFailure.verification("The engine does not have a valid code signature.") }
        var information: CFDictionary?
        guard SecCodeCopySigningInformation(code,SecCSFlags(rawValue:kSecCSSigningInformation),&information) == errSecSuccess,
              let dictionary = information as? [String:Any], let team = dictionary[kSecCodeInfoTeamIdentifier as String] as? String, !team.isEmpty else { throw OperationFailure.verification("A Developer ID signature is required for downloadable engines. This development build has no trusted signing identity.") }
        guard team.range(of:#"^[A-Z0-9]{10}$"#,options:.regularExpression) != nil else { throw OperationFailure.verification("Invalid signing team.") }
        var requirement: SecRequirement?
        let rule = "anchor apple generic and certificate leaf[subject.OU] = \"\(team)\" and certificate 1[field.1.2.840.113635.100.6.2.6] exists and certificate leaf[field.1.2.840.113635.100.6.1.13] exists"
        guard SecRequirementCreateWithString(rule as CFString,SecCSFlags(rawValue:0),&requirement) == errSecSuccess,
              SecStaticCodeCheckValidity(code,SecCSFlags(rawValue:kSecCSStrictValidate),requirement) == errSecSuccess else { throw OperationFailure.verification("A trusted Developer ID Application certificate is required.") }
        return team
    }
    public static func verify(_ bundle: URL, trustedTeam: String) throws -> InstalledEnginePack {
        guard try signingTeam(bundle) == trustedTeam else { throw OperationFailure.verification("The engine was not signed by this app's publisher.") }
        let manifestURL = bundle.appendingPathComponent("Contents/Resources/engine.json")
        guard (try manifestURL.resourceValues(forKeys:[.fileSizeKey]).fileSize ?? 0) < 1024 * 1024 else { throw OperationFailure.resourceLimit }
        let manifest = try JSONDecoder().decode(EnginePackManifest.self,from:Data(contentsOf:manifestURL))
        #if arch(arm64)
        let architecture = "arm64"
        #else
        let architecture = "x86_64"
        #endif
        let version = ProcessInfo.processInfo.operatingSystemVersion
        let os = "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
        guard manifest.schemaVersion == 1, knownIDs.contains(manifest.id),
              manifest.version.range(of:#"^[0-9]+(\.[0-9]+){1,3}$"#,options:.regularExpression) != nil,
              manifest.minimumAppVersion.compare(appVersion,options:.numeric) != .orderedDescending,
              manifest.minimumOSVersion.compare(os,options:.numeric) != .orderedDescending,
              manifest.architectures.contains(architecture), !manifest.licenses.isEmpty,
              manifest.installedBytes > 0, manifest.files.count <= 50000 else { throw OperationFailure.verification("This engine pack is incompatible with the app or Mac.") }
        for (relative,hash) in manifest.files {
            _ = try ArchiveEngine.safeName(relative)
            let path = bundle.appendingPathComponent(relative)
            let values = try path.resourceValues(forKeys:[.isRegularFileKey,.isSymbolicLinkKey])
            guard path.resolvingSymlinksInPath().path.hasPrefix(bundle.resolvingSymlinksInPath().path + "/"), values.isRegularFile == true, values.isSymbolicLink != true, try FileDigest.sha256(path) == hash else { throw OperationFailure.verification("An engine file failed its integrity check.") }
        }
        for relative in manifest.tools.values {
            guard manifest.files[relative] != nil, FileManager.default.isExecutableFile(atPath:bundle.appendingPathComponent(relative).path), try signingTeam(bundle.appendingPathComponent(relative)) == trustedTeam else { throw OperationFailure.verification("An engine executable is missing, unsigned, or untrusted.") }
        }
        for relative in manifest.licenses { guard manifest.files[relative] != nil else { throw OperationFailure.verification("Engine license information is missing.") } }
        for relative in (manifest.models ?? [:]).values { guard manifest.files[relative] != nil else { throw OperationFailure.verification("Transcription model integrity information is missing.") } }
        return InstalledEnginePack(location:bundle,manifest:manifest)
    }
    public static func installed(root: URL = defaultRoot) -> [InstalledEnginePack] {
        guard let team = try? signingTeam(publisherCodeURL) else { return [] }
        return knownIDs.sorted().compactMap { id in
            guard let name = try? String(contentsOf:root.appendingPathComponent(id + ".current"),encoding:.utf8), name == URL(fileURLWithPath:name).lastPathComponent else { return nil }
            return try? verify(root.appendingPathComponent(name),trustedTeam:team)
        }
    }
    public static func install(_ bundle: URL, root: URL = defaultRoot) throws -> InstalledEnginePack {
        let team = try signingTeam(publisherCodeURL)
        let pack = try verify(bundle,trustedTeam:team)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        let next = root.appendingPathComponent(".install-\(UUID().uuidString).bundle")
        try FileManager.default.copyItem(at:bundle,to:next)
        defer { try? FileManager.default.removeItem(at:next) }
        _ = try verify(next,trustedTeam:team)
        let target = root.appendingPathComponent(pack.id + "-" + pack.manifest.version + ".bundle")
        let pointer = root.appendingPathComponent(pack.id + ".current")
        let previous = root.appendingPathComponent(pack.id + ".previous")
        if FileManager.default.fileExists(atPath:target.path) {
            let existing = try verify(target,trustedTeam:team)
            guard existing.manifest.files == pack.manifest.files else { throw OperationFailure.verification("An engine update reused an existing version. Publish it under a new version.") }
        } else { try FileManager.default.moveItem(at:next,to:target) }
        if let old = try? Data(contentsOf:pointer) { try old.write(to:previous,options:.atomic) }
        try Data(target.lastPathComponent.utf8).write(to:pointer,options:.atomic)
        return try verify(target,trustedTeam:team)
    }
    public static func rollback(_ id: String, root: URL = defaultRoot) throws {
        guard knownIDs.contains(id) else { throw OperationFailure.invalidOptions("Unknown engine pack.") }
        let previous = root.appendingPathComponent(id + ".previous"), pointer = root.appendingPathComponent(id + ".current")
        let name = try String(contentsOf:previous,encoding:.utf8)
        guard name == URL(fileURLWithPath:name).lastPathComponent else { throw OperationFailure.verification("Invalid previous engine path.") }
        _ = try verify(root.appendingPathComponent(name),trustedTeam:signingTeam(publisherCodeURL))
        let current = try Data(contentsOf:pointer)
        try Data(name.utf8).write(to:pointer,options:.atomic); try current.write(to:previous,options:.atomic)
    }
    public static func deactivate(_ id: String, root: URL = defaultRoot) throws {
        guard knownIDs.contains(id) else { throw OperationFailure.invalidOptions("Unknown engine pack.") }
        // Versioned files stay immutable while existing jobs may still hold them.
        // Removing the active pointer affects only future app/CLI engine snapshots.
        try FileManager.default.removeItem(at:root.appendingPathComponent(id + ".current"))
    }
    public static func download(_ entry: EngineDownload, root: URL = defaultRoot) async throws -> InstalledEnginePack {
        guard entry.url.scheme == "https", knownIDs.contains(entry.id), entry.downloadBytes > 0, entry.downloadBytes <= 4 * 1024 * 1024 * 1024 else { throw OperationFailure.invalidInput("Invalid engine download.") }
        // Entries must come from the catalog sealed inside the signed app, never an unsigned remote manifest.
        let catalogURL = Bundle.main.url(forResource:"EngineCatalog",withExtension:"json")
        let catalog = try catalogURL.map { try JSONDecoder().decode([EngineDownload].self,from:Data(contentsOf:$0)) } ?? []
        guard catalog.contains(where: { $0.id == entry.id && $0.version == entry.version && $0.sha256 == entry.sha256 && $0.url == entry.url && $0.downloadBytes == entry.downloadBytes }) else { throw OperationFailure.verification("This download is not in the app's trusted catalog.") }
        let (temporary,response) = try await URLSession.shared.download(from:entry.url)
        defer { try? FileManager.default.removeItem(at:temporary) }
        guard response.url?.scheme == "https", (response as? HTTPURLResponse)?.statusCode == 200,
              Int64(try temporary.resourceValues(forKeys:[.fileSizeKey]).fileSize ?? 0) == entry.downloadBytes,
              try FileDigest.sha256(temporary) == entry.sha256 else { throw OperationFailure.verification("The engine download failed verification.") }
        let stage = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString,isDirectory:true)
        defer { try? FileManager.default.removeItem(at:stage) }
        _ = try ArchiveEngine.extract(temporary,to:stage)
        let children = try FileManager.default.contentsOfDirectory(at:stage,includingPropertiesForKeys:nil)
        guard children.count == 1, children[0].pathExtension == "bundle" else { throw OperationFailure.verification("Engine download has an invalid layout.") }
        // Archive extraction removes executable permissions; restore only declared executables after the sealed bundle is verified.
        let downloadedManifest = children[0].appendingPathComponent("Contents/Resources/engine.json")
        guard (try downloadedManifest.resourceValues(forKeys:[.fileSizeKey]).fileSize ?? 0) < 1024*1024 else { throw OperationFailure.resourceLimit }
        let manifest = try JSONDecoder().decode(EnginePackManifest.self,from:Data(contentsOf:downloadedManifest))
        guard manifest.id == entry.id, manifest.version == entry.version else { throw OperationFailure.verification("Downloaded engine identity does not match the catalog.") }
        for relative in manifest.tools.values { _ = try ArchiveEngine.safeName(relative); try FileManager.default.setAttributes([.posixPermissions:0o755],ofItemAtPath:children[0].appendingPathComponent(relative).path) }
        // The bundle anchor is authenticated by the outer code signature. Its
        // signature seals this manifest, so it cannot hash itself in the manifest.
        let anchor = children[0].appendingPathComponent("Contents/MacOS/pack-anchor")
        if (try? anchor.resourceValues(forKeys:[.isRegularFileKey]).isRegularFile) == true { try FileManager.default.setAttributes([.posixPermissions:0o755],ofItemAtPath:anchor.path) }
        return try install(children[0],root:root)
    }
}
