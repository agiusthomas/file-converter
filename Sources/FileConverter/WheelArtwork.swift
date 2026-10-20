import SwiftUI
import ConverterCore

/// The same rounded petal outline as the AppKit wheel, expressed in y-down space.
struct WheelPetal: Shape {
    let index: Int
    let count: Int

    func path(in rect: CGRect) -> Path {
        guard count > 0 else { return Path() }
        let scale = min(rect.width, rect.height) / 420
        let centre = CGPoint(x: rect.midX, y: rect.midY)
        let step = 360 / Double(count)
        let start = -90 + Double(index) * step - step / 2 + 2
        let end = -90 + Double(index) * step + step / 2 - 2
        func point(_ radius: Double, _ degrees: Double) -> CGPoint {
            let angle = degrees * .pi / 180
            return CGPoint(x: centre.x + radius * scale * cos(angle),
                           y: centre.y + radius * scale * sin(angle))
        }
        var path = Path()
        path.move(to: point(74, start))
        path.addLine(to: point(172, start))
        path.addCurve(to: point(186, start + 5), control1: point(186, start), control2: point(186, start))
        path.addArc(center: centre, radius: 186 * scale, startAngle: .degrees(start + 5), endAngle: .degrees(end - 5), clockwise: false)
        path.addCurve(to: point(172, end), control1: point(186, end), control2: point(186, end))
        path.addLine(to: point(74, end))
        path.addCurve(to: point(62, end - 5), control1: point(62, end), control2: point(62, end))
        path.addArc(center: centre, radius: 62 * scale, startAngle: .degrees(end - 5), endAngle: .degrees(start + 5), clockwise: true)
        path.addCurve(to: point(74, start), control1: point(62, start), control2: point(62, start))
        path.closeSubpath()
        return path
    }
}

struct WheelArtwork: View {
    let labels: [String]
    let selected: Int?
    let title: String
    let subtitle: String
    var showsFormatLabels = false
    init(formats: [ImageFormat], selected: Int?, title: String, subtitle: String, showsFormatLabels: Bool = false) { self.labels = formats.map(\.title); self.selected = selected; self.title = title; self.subtitle = subtitle; self.showsFormatLabels = showsFormatLabels }
    init(labels: [String], selected: Int?, title: String, subtitle: String, showsFormatLabels: Bool = false) { self.labels = labels; self.selected = selected; self.title = title; self.subtitle = subtitle; self.showsFormatLabels = showsFormatLabels }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        GeometryReader { proxy in
            let scale = min(proxy.size.width, proxy.size.height) / 420
            let centre = CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2)
            ZStack {
                GlacierGlassGroup {
                    ZStack {
                        ForEach(labels.indices, id: \.self) { index in
                            GlacierGlass(shape: WheelPetal(index: index, count: labels.count), selected: selected == index)
                                .shadow(color: .black.opacity(0.13), radius: 7 * scale, y: 3 * scale)
                        }
                        GlacierGlass(shape: Circle())
                            .frame(width: 100 * scale, height: 100 * scale)
                            .position(centre)
                    }
                }
                if let selected {
                    // Keep this outside the glass container: macOS desaturates
                    // the container's tint when the panel does not activate.
                    WheelPetal(index: selected, count: labels.count)
                        .fill(Theme.selection.opacity(0.94))
                        .overlay {
                            WheelPetal(index: selected, count: labels.count)
                                .stroke(contrast == .increased ? Color.white : Theme.accent.opacity(0.8), lineWidth: contrast == .increased ? 2 : 1)
                        }
                }
                VStack(spacing: 5 * scale) {
                    Text(title).font(.system(size: showsFormatLabels ? 35 * scale : 13, weight: .bold))
                        .foregroundStyle(Theme.accent).lineLimit(1).minimumScaleFactor(0.7)
                    Text(subtitle).font(.system(size: showsFormatLabels ? 13 * scale : 10, weight: .medium))
                        .foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.7)
                }
                .frame(width: 112 * scale)
                .position(centre)
                if showsFormatLabels {
                    ForEach(Array(labels.enumerated()), id: \.offset) { index, format in
                        let angle = -Double.pi / 2 + Double(index) * 2 * .pi / Double(labels.count)
                        Text(format)
                            .font(.system(size: 17 * scale, weight: .bold, design: .monospaced))
                            .foregroundStyle(selected == index ? .white : Theme.ink)
                            .position(x: centre.x + cos(angle) * 126 * scale, y: centre.y + sin(angle) * 126 * scale)
                    }
                }
            }
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.15), value: selected)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
