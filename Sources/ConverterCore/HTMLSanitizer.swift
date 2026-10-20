import Foundation

public enum HTMLSanitizer {
    /// Reconstruct a small static layout vocabulary. A forward-only tokenizer
    /// avoids repeated regex scans over malformed or unterminated HTML. No input
    /// attributes, resource URLs, scripts, CSS, forms or objects survive.
    public static func staticDocument(_ input: String) throws -> String {
        guard input.utf8.count <= 32 * 1024 * 1024 else { throw OperationFailure.resourceLimit }
        let allowed: Set<String> = ["p","br","div","span","h1","h2","h3","h4","h5","h6","b","strong","i","em","u","s","ul","ol","li","table","tr","td","th","thead","tbody","pre","code","blockquote","hr","a"]
        let blocked: Set<String> = ["script","style","iframe","object","svg","math","template"]
        var result = "", cursor = input.startIndex, suppressed: String?, depth = 0
        func text(_ value: Substring) -> String { value.replacingOccurrences(of:"<",with:"&lt;").replacingOccurrences(of:">",with:"&gt;") }
        while cursor < input.endIndex {
            try Task.checkCancellation()
            guard let start = input[cursor...].firstIndex(of:"<") else { if suppressed == nil { result += text(input[cursor...]) }; break }
            if suppressed == nil { result += text(input[cursor..<start]) }
            if input[start...].hasPrefix("<!--") {
                guard let end = input.range(of:"-->",range:input.index(start,offsetBy:4)..<input.endIndex) else { break }
                cursor = end.upperBound; continue
            }
            guard let end = input[start...].firstIndex(of:">") else { if suppressed == nil { result += text(input[start...]) }; break }
            let token = input[input.index(after:start)..<end].trimmingCharacters(in:.whitespacesAndNewlines)
            let closing = token.hasPrefix("/")
            let body = closing ? token.dropFirst().drop(while:{$0.isWhitespace}) : token[...]
            let name = String(body.prefix(while:{$0.isASCII && ($0.isLetter || $0.isNumber)})).lowercased()
            if let current = suppressed {
                if name == current { if closing { depth -= 1; if depth == 0 { suppressed = nil } } else { depth += 1 } }
            } else if blocked.contains(name), !closing { suppressed = name; depth = 1 }
            else if allowed.contains(name) { result += "<" + (closing ? "/" : "") + name + ">" }
            cursor = input.index(after:end)
        }
        return "<!doctype html><html><head><meta charset=\"utf-8\"></head><body>" + result + "</body></html>"
    }
}
