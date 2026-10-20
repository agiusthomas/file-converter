import Foundation

public enum NamingPolicy {
    public static func stem(template: String?, source: URL, profile: OutputProfile, index: Int, fallbackSuffix: String = "") throws -> String {
        let template = template?.isEmpty == false ? template! : "{name}" + fallbackSuffix
        let result = template.replacingOccurrences(of:"{name}",with:source.deletingPathExtension().lastPathComponent).replacingOccurrences(of:"{format}",with:profile.id).replacingOccurrences(of:"{index}",with:String(index))
        guard !result.contains("{"), !result.contains("}"), !result.isEmpty, result.utf8.count <= 200, !result.contains("/"), !result.contains("\\"), !result.contains(":"), result != ".", result != "..", !result.unicodeScalars.contains(where:{CharacterSet.controlCharacters.contains($0)}) else { throw OperationFailure.invalidOptions("Filename templates support {name}, {format}, and {index}, without path separators.") }; return result
    }
}
