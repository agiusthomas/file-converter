// Run from the repository root:
// xcrun swiftc -module-cache-path .build/module-cache Sources/FileConverter/GlacierBrand.swift \
//   Sources/FileConverter/GlacierTheme.swift scripts/generate-app-icon.swift -o build/generate-app-icon
// build/generate-app-icon
import AppKit

@main
struct GenerateAppIcon {
    static func color(_ hex: UInt32) -> NSColor {
        NSColor(srgbRed: Double((hex >> 16) & 255) / 255,
                green: Double((hex >> 8) & 255) / 255,
                blue: Double(hex & 255) / 255, alpha: 1)
    }

    static func render(pixels: Int, to url: URL) throws {
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                                     bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                     isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        let graphics = NSGraphicsContext(bitmapImageRep: bitmap)!
        NSGraphicsContext.current = graphics
        let context = graphics.cgContext
        context.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)

        let tile = NSBezierPath(roundedRect: NSRect(x: 64, y: 64, width: 896, height: 896),
                                xRadius: 200, yRadius: 200)
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = color(0x182B49).withAlphaComponent(0.20)
        shadow.shadowBlurRadius = 24
        shadow.shadowOffset = NSSize(width: 0, height: -12)
        shadow.set()
        color(0x2164CF).setFill()
        tile.fill()
        NSGraphicsContext.restoreGraphicsState()
        NSGradient(starting: color(0x2878F0), ending: color(0x2164CF))!.draw(in: tile, angle: -90)
        color(0xFFFFFF).withAlphaComponent(0.22).setStroke()
        tile.lineWidth = 2
        tile.stroke()

        let iceRect = CGRect(x: 154, y: 154, width: 716, height: 716)
        let colors: [UInt32] = [0xFFFFFF, 0xB7CCE8, 0x6AAEFF]
        for (index, facet) in GlacierBrand.facets.enumerated() {
            let path = NSBezierPath()
            for (vertex, point) in facet.enumerated() {
                let mapped = CGPoint(x: iceRect.minX + point.x * iceRect.width,
                                     y: iceRect.maxY - point.y * iceRect.height)
                if vertex == 0 { path.move(to: mapped) } else { path.line(to: mapped) }
            }
            path.close()
            color(colors[index]).setFill()
            path.fill()
        }

        let png = bitmap.representation(using: .png, properties: [:])!
        try png.write(to: url)
    }

    static func main() throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Configuration/Assets.xcassets", isDirectory: true)
        let icons = root.appendingPathComponent("AppIcon.appiconset", isDirectory: true)
        try FileManager.default.createDirectory(at: icons, withIntermediateDirectories: true)
        var images: [[String: String]] = []
        for size in [16, 32, 128, 256, 512] {
            for scale in [1, 2] {
                let filename = "glacier-\(size)@\(scale)x.png"
                try render(pixels: size * scale, to: icons.appendingPathComponent(filename))
                images.append(["idiom": "mac", "size": "\(size)x\(size)",
                               "scale": "\(scale)x", "filename": filename])
            }
        }
        let info: [String: Any] = ["author": "xcode", "version": 1]
        try JSONSerialization.data(withJSONObject: ["images": images, "info": info], options: [.prettyPrinted, .sortedKeys])
            .write(to: icons.appendingPathComponent("Contents.json"))
        try JSONSerialization.data(withJSONObject: ["info": info], options: [.prettyPrinted, .sortedKeys])
            .write(to: root.appendingPathComponent("Contents.json"))
        print("Generated all 10 macOS app-icon sizes in \(icons.path)")
    }
}
