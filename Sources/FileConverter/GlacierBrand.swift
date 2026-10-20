import AppKit
import SwiftUI

enum GlacierBrand {
    static let name = "Glacier File Converter"

    static var versionDescription: String {
        guard let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String else {
            return "Development build"
        }
        if let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String {
            return "Version \(version) (\(build))"
        }
        return "Version \(version)"
    }

    // Shared, normalized artwork for the sidebar, menu bar, and app-icon generator.
    // Coordinates use a top-left origin.
    static let facets: [[CGPoint]] = [
        [.init(x: 0.42, y: 0.08), .init(x: 0.49, y: 0.56),
         .init(x: 0.12, y: 0.72), .init(x: 0.23, y: 0.35)],
        [.init(x: 0.42, y: 0.08), .init(x: 0.70, y: 0.27),
         .init(x: 0.83, y: 0.68), .init(x: 0.49, y: 0.56)],
        [.init(x: 0.12, y: 0.72), .init(x: 0.49, y: 0.56),
         .init(x: 0.83, y: 0.68), .init(x: 0.50, y: 0.92)]
    ]

    static func markPath(in rect: CGRect, facetScale: CGFloat = 0.94) -> Path {
        var path = Path()
        for facet in facets {
            let center = CGPoint(x: facet.map(\.x).reduce(0, +) / CGFloat(facet.count),
                                 y: facet.map(\.y).reduce(0, +) / CGFloat(facet.count))
            let points = facet.map {
                CGPoint(x: rect.minX + (center.x + ($0.x - center.x) * facetScale) * rect.width,
                        y: rect.minY + (center.y + ($0.y - center.y) * facetScale) * rect.height)
            }
            path.addLines(points)
            path.closeSubpath()
        }
        return path
    }

    static var menuBarImage: NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { rect in
            NSColor.black.setFill()
            NSGraphicsContext.current?.cgContext.addPath(markPath(in: rect).cgPath)
            NSGraphicsContext.current?.cgContext.fillPath()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = name
        return image
    }
}

struct GlacierMark: Shape {
    func path(in rect: CGRect) -> Path { GlacierBrand.markPath(in: rect) }
}

struct GlacierSidebarBrand: View {
    var body: some View {
        HStack(spacing: 9) {
            GlacierMark().fill(Theme.ink).frame(width: 24, height: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text("Glacier").font(.system(size: 17, weight: .semibold))
                Text("File Converter").font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
            }
            .fixedSize()
        }
        // The previous single-line label plus 30pt padding occupied 50pt.
        .frame(height: 50, alignment: .topLeading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(GlacierBrand.name)
    }
}
