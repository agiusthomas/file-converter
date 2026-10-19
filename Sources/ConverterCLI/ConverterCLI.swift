import Foundation
import ConverterCore
import Darwin

@main struct ConverterCLI {
    static func main() async {
        var args = Array(CommandLine.arguments.dropFirst())
        guard let command = args.first, !["--help", "-h"].contains(command) else { printHelp(); return }
        args.removeFirst()
        if command == "capabilities" {
            let data = try! JSONSerialization.data(withJSONObject: ["imageOutputs": CapabilityRegistry().writableFormats.map(\.rawValue)], options: [.prettyPrinted, .sortedKeys])
            print(String(decoding: data, as: UTF8.self)); return
        }
        guard command == "convert" else { fail("Unknown command: \(command)"); return }
        var format: ImageFormat?
        var output: URL?
        var quality = 0.9
        var metadata = true
        var sources: [URL] = []
        while !args.isEmpty {
            let value = args.removeFirst()
            switch value {
            case "--to":
                guard !args.isEmpty else { fail("--to needs a format"); return }
                format = ImageFormat.fromExtension(args.removeFirst())
            case "--output":
                guard !args.isEmpty else { fail("--output needs a folder"); return }
                output = URL(fileURLWithPath: args.removeFirst(), isDirectory: true)
            case "--quality":
                guard !args.isEmpty, let number = Double(args.removeFirst()), (0...1).contains(number) else { fail("Quality must be between 0 and 1"); return }
                quality = number
            case "--strip-metadata": metadata = false
            default:
                guard !value.hasPrefix("--") else { fail("Unknown option: \(value)"); return }
                sources.append(URL(fileURLWithPath: value))
            }
        }
        guard let format, !sources.isEmpty else { fail("Specify --to FORMAT and one or more image paths."); return }
        let converter = ImageConverter()
        var failed = false
        for source in sources {
            do {
                let result = try await converter.convert(.init(source: source, format: format, options: .init(quality: quality, preserveMetadata: metadata), destinationDirectory: output))
                let data = try JSONSerialization.data(withJSONObject: ["source": result.source.path, "output": result.output.path, "width": result.width, "height": result.height, "pages": result.pageCount, "bytes": result.byteCount, "notices": result.notices], options: [.sortedKeys])
                print(String(decoding: data, as: UTF8.self))
            } catch { failed = true; FileHandle.standardError.write(Data("\(source.lastPathComponent): \(error.localizedDescription)\n".utf8)) }
        }
        if failed { exit(1) }
    }
    private static func fail(_ message: String) { FileHandle.standardError.write(Data((message + "\n").utf8)); exit(2) }
    private static func printHelp() {
        print("""
        Local image converter

        convert-file capabilities
        convert-file convert --to jpg [--quality 0.9] [--strip-metadata] [--output FOLDER] IMAGE...

        Results are verified and saved beside the source unless --output is set.
        Existing files are never replaced. PNG/JPG/TIFF/HEIC/BMP/PDF outputs
        are available when supported by this Mac. PDF input is not implemented.
        """)
    }
}
