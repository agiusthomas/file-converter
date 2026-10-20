// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FileConverter",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "FileConverter", targets: ["FileConverter"]),
        .executable(name: "convert-file", targets: ["ConverterCLI"]),
        .executable(name: "converter-worker", targets: ["ConverterWorker"]),
        .library(name: "ConverterCore", targets: ["ConverterCore"])
    ],
    targets: [
        .target(name: "ArchiveBridge", linkerSettings: [.linkedLibrary("dl")]),
        .target(name: "WebPBridge", exclude: ["libwebp/COPYING", "libwebp/PATENTS", "libwebp/AUTHORS"], publicHeadersPath: "include", cSettings: [.headerSearchPath("libwebp"), .headerSearchPath("libwebp/src")]),
        .target(name: "ConverterCore", dependencies: ["ArchiveBridge", "WebPBridge"]),
        .executableTarget(name: "ConverterWorker", dependencies: ["ConverterCore"]),
        .executableTarget(name: "FileConverter", dependencies: ["ConverterCore"], resources: [.copy("Resources/Sounds")]),
        .executableTarget(name: "ConverterCLI", dependencies: ["ConverterCore"]),
        .testTarget(name: "ConverterCoreTests", dependencies: ["ConverterCore"]),
        .testTarget(name: "FileConverterTests", dependencies: ["FileConverter"])
    ],
    swiftLanguageModes: [.v5]
)
