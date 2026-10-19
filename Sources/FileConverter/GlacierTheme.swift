import AppKit
import SwiftUI

/// One adaptive palette for the workspace and the AppKit conversion panel.
enum Theme {
    static let accentColor = adaptive("Glacier accent", light: 0x2878F0, dark: 0x6AAEFF)
    static let inkColor = adaptive("Glacier ink", light: 0x182B49, dark: 0xEDF4FF)
    static let selectionColor = adaptive("Glacier selection", light: 0x2164CF, dark: 0x285AA4)
    static let accent = Color(nsColor: accentColor)
    static let ink = Color(nsColor: inkColor)
    static let selection = Color(nsColor: selectionColor)
    static let paper = Color(nsColor: adaptive("Glacier background", light: 0xEEF5FF, dark: 0x101C30))
    static let surface = Color(nsColor: adaptive("Glacier surface", light: 0xF8FBFF, dark: 0x19283E))
    static let border = Color(nsColor: adaptive("Glacier border", light: 0xB7CCE8, dark: 0x425976))

    private static func adaptive(_ name: String, light: UInt32, dark: UInt32) -> NSColor {
        NSColor(name: NSColor.Name(name)) { appearance in
            let hex = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: Double((hex >> 16) & 0xFF) / 255,
                           green: Double((hex >> 8) & 0xFF) / 255,
                           blue: Double(hex & 0xFF) / 255, alpha: 1)
        }
    }
}

/// Small, shared glass surfaces. Never stack a glass content card inside another.
struct GlacierGlass<Outline: Shape>: View {
    var shape: Outline
    var selected = false
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        material
            .overlay {
                shape.stroke(contrast == .increased ? Theme.ink.opacity(0.65) : Theme.border.opacity(0.65),
                             lineWidth: contrast == .increased ? 1.5 : 0.75)
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    @ViewBuilder private var material: some View {
        if reduceTransparency {
            shape.fill(selected ? Theme.selection : Theme.surface)
        } else if #available(macOS 26.0, *) {
            Color.clear
                .glassEffect(.regular.tint(selected ? Theme.selection : Theme.accent.opacity(0.06)), in: shape)
        } else {
            shape.fill(.regularMaterial)
                .overlay { shape.fill(selected ? Theme.selection.opacity(0.94) : Theme.accent.opacity(0.04)) }
        }
    }
}

struct GlacierCard: ViewModifier {
    var radius: CGFloat = 14
    @Environment(\.colorSchemeContrast) private var contrast
    func body(content: Content) -> some View {
        content.background(Theme.surface, in: RoundedRectangle(cornerRadius: radius))
            .overlay {
                RoundedRectangle(cornerRadius: radius)
                    .strokeBorder(Theme.border.opacity(contrast == .increased ? 1 : 0.55),
                                  lineWidth: contrast == .increased ? 1.5 : 0.75)
            }
    }
}

struct GlacierSidebarSurface: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var body: some View {
        if reduceTransparency {
            Theme.surface
        } else {
            SidebarVibrancy().overlay(Theme.paper.opacity(0.35))
        }
    }
}

private struct SidebarVibrancy: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .sidebar
        view.blendingMode = .behindWindow
        view.state = .followsWindowActiveState
        return view
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

/// Native styles retain keyboard focus, disabled behavior, and accessibility.
struct GlacierActionStyle: PrimitiveButtonStyle {
    var prominent = false
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    func makeBody(configuration: Configuration) -> some View {
        if #available(macOS 26.0, *), !reduceTransparency {
            if prominent {
                Button(configuration).buttonStyle(.glassProminent).tint(Theme.selection)
            } else {
                Button(configuration).buttonStyle(.glass).tint(nil)
            }
        } else if prominent {
            Button(configuration).buttonStyle(.borderedProminent).tint(Theme.selection)
        } else {
            Button(configuration).buttonStyle(.bordered)
        }
    }
}

/// Keep separate petals separate: container spacing must not bridge their gaps.
struct GlacierGlassGroup<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: 0) { content }
        } else {
            content
        }
    }
}
