// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FileConverter",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "FileConverter", targets: ["FileConverter"]),
        .executable(name: "convert-file", targets: ["ConverterCLI"]),
        .library(name: "ConverterCore", targets: ["ConverterCore"])
    ],
    targets: [
        .target(name: "ConverterCore"),
        .executableTarget(name: "FileConverter", dependencies: ["ConverterCore"]),
        .executableTarget(name: "ConverterCLI", dependencies: ["ConverterCore"]),
        .testTarget(name: "ConverterCoreTests", dependencies: ["ConverterCore"])
    ],
    swiftLanguageModes: [.v5]
)
