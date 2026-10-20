import Foundation

public enum PathPolicy {
    /// Compare filesystem paths after resolving macOS aliases such as /var and
    /// /private/var. Never derive member names by slicing unrelated URL strings.
    public static func relativePath(of child: URL, under root: URL) throws -> String {
        let base = root.resolvingSymlinksInPath().standardizedFileURL.pathComponents
        let path = child.resolvingSymlinksInPath().standardizedFileURL.pathComponents
        guard path.count >= base.count, Array(path.prefix(base.count)) == base else { throw OperationFailure.invalidInput("A file lies outside its expected folder.") }
        return path.dropFirst(base.count).joined(separator:"/")
    }
}
