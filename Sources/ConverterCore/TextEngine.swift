import Foundation

public struct SubtitleCue: Equatable, Sendable { public var start: Double; public var end: Double; public var text: String }
public enum TextEngine {
    public static func read(_ url: URL, encoding: String = "auto") throws -> String {
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= 32 * 1024 * 1024 else { throw OperationFailure.resourceLimit }
        let data = try Data(contentsOf: url)
        let kind: String.Encoding = data.starts(with: [0xff,0xfe]) || data.starts(with: [0xfe,0xff]) ? .utf16 : stringEncoding(encoding)
        guard let text = String(data: data, encoding: kind) ?? (encoding == "auto" ? String(data:data,encoding:.windowsCP1252) : nil) else { throw OperationFailure.invalidInput("Text cannot be decoded with the selected encoding.") }
        return text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n").trimmingCharacters(in: CharacterSet(charactersIn: "\u{feff}"))
    }
    public static func stringEncoding(_ value: String) -> String.Encoding { switch value { case "utf-16": return .utf16; case "windows-1252": return .windowsCP1252; case "ascii": return .ascii; default: return .utf8 } }
    public static func write(_ text: String, to url: URL, options: OperationOptions) throws {
        let text = options.lineEndings == "crlf" ? text.replacingOccurrences(of: "\n", with: "\r\n") : text
        guard let data = text.data(using: stringEncoding(options.encoding), allowLossyConversion: false) else { throw OperationFailure.invalidOptions("The selected encoding cannot represent every character. Choose UTF-8.") }
        try data.write(to: url, options: .atomic)
        guard String(data: try Data(contentsOf: url), encoding: stringEncoding(options.encoding)) != nil else { throw OperationFailure.verification("Text failed to reopen.") }
    }
    public static func cues(_ source: String) throws -> [SubtitleCue] {
        let source = source.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        let blocks = source.components(separatedBy: "\n\n").filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        var cues: [SubtitleCue] = []
        for block in blocks {
            let lines = block.components(separatedBy: "\n")
            if block.hasPrefix("WEBVTT") || block.hasPrefix("NOTE") { continue }
            guard !block.hasPrefix("STYLE"), !block.hasPrefix("REGION"), let index = lines.firstIndex(where: { $0.contains("-->") }), index + 1 < lines.count else { throw OperationFailure.invalidInput("Unsupported or malformed subtitle block.") }
            let times = lines[index].components(separatedBy: "-->").map { $0.trimmingCharacters(in: .whitespaces) }
            guard times.count == 2, !times[1].contains(" "), let start = timestamp(times[0]), let end = timestamp(times[1]), end > start else { throw OperationFailure.invalidInput("Invalid subtitle timing or unsupported cue settings.") }
            if let previous = cues.last, start < previous.start { throw OperationFailure.invalidInput("Subtitle cues are out of order.") }
            cues.append(.init(start: start, end: end, text: lines[(index+1)...].joined(separator: "\n")))
            guard cues.count <= 100000 else { throw OperationFailure.resourceLimit }
        }
        guard !cues.isEmpty else { throw OperationFailure.invalidInput("No valid subtitle cues were found.") }
        return cues
    }
    private static func timestamp(_ text: String) -> Double? {
        guard text.range(of:#"^(?:[0-9]{2,3}:)?[0-9]{2}:[0-9]{2}[,.][0-9]{3}$"#,options:.regularExpression) != nil else { return nil }
        let parts = text.replacingOccurrences(of: ",", with: ".").split(separator: ":").map(String.init)
        guard (2...3).contains(parts.count), let seconds = Double(parts.last!), (0..<60).contains(seconds), let minutes = Double(parts[parts.count-2]), (0..<60).contains(minutes), let hours = parts.count == 3 ? Double(parts[0]) : 0, hours >= 0, hours < 1000 else { return nil }
        return hours * 3600 + minutes * 60 + seconds
    }
    public static func subtitle(_ cues: [SubtitleCue], format: String, offset: Double) throws -> String {
        func stamp(_ seconds: Double) -> String {
            let milliseconds = Int((seconds * 1000).rounded())
            return String(format: "%02d:%02d:%02d%@%03d", milliseconds / 3600000, milliseconds / 60000 % 60, milliseconds / 1000 % 60, format == "srt" ? "," : ".", milliseconds % 1000)
        }
        if format == "txt" { return cues.map(\.text).joined(separator: "\n\n") + "\n" }
        guard ["srt","vtt"].contains(format) else { throw OperationFailure.unsupported("Unsupported subtitle format.") }
        var output = format == "vtt" ? "WEBVTT\n\n" : ""
        for (index,cue) in cues.enumerated() {
            guard cue.start + offset >= 0, cue.end + offset < 3600000 else { throw OperationFailure.invalidOptions("The timing offset puts a cue outside the supported range.") }
            if format == "srt" { output += "\(index + 1)\n" }
            output += "\(stamp(cue.start + offset)) --> \(stamp(cue.end + offset))\n\(cue.text)\n\n"
        }
        _ = try self.cues(output)
        return output
    }
    public static func table(_ text: String, delimiter: Character) throws -> [[String]] {
        var rows: [[String]] = [], row: [String] = [], cell = "", quoted = false, closed = false
        var iterator = text.makeIterator(); var next = iterator.next()
        while let c = next {
            next = iterator.next()
            if quoted {
                if c == "\"" { if next == "\"" { cell.append("\""); next = iterator.next() } else { quoted = false; closed = true } }
                else { cell.append(c) }
            } else if c == "\"", cell.isEmpty, !closed { quoted = true }
            else if c == delimiter { row.append(cell); cell = ""; closed = false }
            else if c == "\n" { row.append(cell); rows.append(row); row = []; cell = ""; closed = false }
            else { guard !closed else { throw OperationFailure.invalidInput("Unexpected text after a quoted table cell.") }; cell.append(c) }
            guard rows.count <= 1000000, row.count <= 16384 else { throw OperationFailure.resourceLimit }
        }
        guard !quoted else { throw OperationFailure.invalidInput("Unterminated quoted table cell.") }
        if !cell.isEmpty || !row.isEmpty || closed { row.append(cell); rows.append(row) }
        return rows
    }
    public static func delimited(_ rows: [[String]], delimiter: String) -> String {
        rows.map { row in row.map { cell in cell.contains(delimiter) || cell.contains("\"") || cell.contains("\n") ? "\"" + cell.replacingOccurrences(of: "\"", with: "\"\"") + "\"" : cell }.joined(separator: delimiter) }.joined(separator: "\n") + "\n"
    }
    public static func escapedHTML(_ text: String) -> String { text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;") }
}
