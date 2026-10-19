import AppKit
import SwiftUI
import ConverterCore

@MainActor final class WheelPanelController {
    private var panel: NSPanel?
    let registry = CapabilityRegistry()
    var onConversion: (([URL], ImageFormat) -> Void)?
    func show(sources: [URL], at point: NSPoint, clickable: Bool = false) {
        let formats = registry.destinations(for: sources)
        guard !formats.isEmpty else { return }
        dismiss()
        let size = NSSize(width: 420, height: 420)
        let screen = NSScreen.screens.first(where: { $0.frame.contains(point) }) ?? NSScreen.main
        let bounds = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let origin = NSPoint(x: min(max(point.x - 210, bounds.minX), bounds.maxX - size.width),
                             y: min(max(point.y - 210, bounds.minY), bounds.maxY - size.height))
        let panel = WheelPanel(contentRect: NSRect(origin: origin, size: size), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.backgroundColor = .clear; panel.isOpaque = false; panel.hasShadow = false
        panel.hidesOnDeactivate = false; panel.isReleasedWhenClosed = false
        panel.acceptsMouseMovedEvents = true
        let wheel = WheelView(frame: NSRect(origin: .zero, size: size), sources: sources, formats: formats)
        wheel.onChoose = { [weak self] selectedSources, format in
            self?.dismiss(); self?.onConversion?(selectedSources, format)
        }
        wheel.onCancel = { [weak self] in self?.dismiss() }
        panel.contentView = wheel; self.panel = panel
        panel.orderFrontRegardless()
        if clickable { panel.makeKey(); panel.makeFirstResponder(wheel) }
    }
    func dismiss() { panel?.orderOut(nil); panel = nil }
}

private final class WheelPanel: NSPanel { override var canBecomeKey: Bool { true } }

@MainActor private final class WheelView: NSView {
    let sources: [URL]
    let formats: [ImageFormat]
    var selected: Int? {
        didSet {
            guard selected != oldValue else { return }
            artworkState.selected = selected
            updateButtons()
        }
    }
    var onChoose: (([URL], ImageFormat) -> Void)?
    var onCancel: (() -> Void)?
    private let artworkState = WheelArtworkState()
    private var labelButtons: [NSButton] = []
    private var tracking: NSTrackingArea?
    private var geometry: WheelGeometry { WheelGeometry(count: formats.count) }
    override var acceptsFirstResponder: Bool { true }
    init(frame: NSRect, sources: [URL], formats: [ImageFormat]) {
        self.sources = sources; self.formats = formats
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL])
        setAccessibilityRole(.group); setAccessibilityLabel("Conversion wheel")
        let artwork = WheelArtworkHost(rootView: LiveWheelArtwork(state: artworkState, sources: sources, formats: formats))
        artwork.frame = bounds
        artwork.autoresizingMask = [.width, .height]
        artwork.setAccessibilityElement(false)
        addSubview(artwork)
        for (index, format) in formats.enumerated() {
            let angle = Double.pi / 2 - Double(index) * 2 * Double.pi / Double(formats.count)
            let centre = NSPoint(x: 210 + cos(angle) * 126, y: 210 + sin(angle) * 126)
            let button = NSButton(title: format.title, target: self, action: #selector(chooseLabel(_:)))
            button.isBordered = false; button.font = .monospacedSystemFont(ofSize: 14, weight: .bold)
            button.frame = NSRect(x: centre.x - 39, y: centre.y - 16, width: 78, height: 32)
            button.tag = index; button.setAccessibilityLabel("Convert to \(format.title)")
            button.toolTip = "Convert \(sources.count == 1 ? "image" : "images") to \(format.title)"
            addSubview(button); labelButtons.append(button)
        }
        updateButtons()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let tracking = NSTrackingArea(rect: bounds, options: [.activeAlways, .mouseMoved, .mouseEnteredAndExited], owner: self)
        addTrackingArea(tracking); self.tracking = tracking
    }
    private func index(at point: NSPoint) -> Int? { geometry.sector(x: point.x - 210, y: point.y - 210) }
    override func mouseMoved(with event: NSEvent) { selected = index(at: convert(event.locationInWindow, from: nil)) }
    override func mouseExited(with event: NSEvent) { selected = nil }
    override func mouseDown(with event: NSEvent) {
        if let index = index(at: convert(event.locationInWindow, from: nil)) { onChoose?(sources, formats[index]) }
        else { onCancel?() }
    }
    @objc private func chooseLabel(_ sender: NSButton) { onChoose?(sources, formats[sender.tag]) }
    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53: onCancel?()
        case 123, 126: selected = ((selected ?? 0) - 1 + formats.count) % formats.count
        case 124, 125: selected = ((selected ?? -1) + 1) % formats.count
        case 36, 76: if let selected { onChoose?(sources, formats[selected]) }
        default: super.keyDown(with: event)
        }
    }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { updateDrag(sender) }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { updateDrag(sender) }
    override func draggingExited(_ sender: NSDraggingInfo?) { selected = nil }
    private func updateDrag(_ sender: NSDraggingInfo) -> NSDragOperation {
        selected = index(at: convert(sender.draggingLocation, from: nil))
        return selected == nil ? [] : .copy
    }
    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        selected = index(at: convert(sender.draggingLocation, from: nil)); return selected != nil
    }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let selected, CapabilityRegistry().destinations(for: DragMonitor.files(from: sender.draggingPasteboard)).contains(formats[selected]) else { return false }
        let urls = DragMonitor.files(from: sender.draggingPasteboard)
        onChoose?(urls, formats[selected]); return true
    }
    private func updateButtons() {
        for (index, button) in labelButtons.enumerated() {
            button.contentTintColor = selected == index ? .white : Theme.inkColor
            button.setAccessibilityValue(selected == index ? "Selected" : nil)
        }
    }
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateButtons()
    }
}

@MainActor private final class WheelArtworkState: ObservableObject {
    @Published var selected: Int?
}

private struct LiveWheelArtwork: View {
    @ObservedObject var state: WheelArtworkState
    let sources: [URL]
    let formats: [ImageFormat]

    var body: some View {
        WheelArtwork(formats: formats, selected: state.selected,
                     title: state.selected.map { formats[$0].title }
                        ?? (sources.count == 1 ? sources[0].pathExtension.uppercased() : "\(sources.count) FILES"),
                     subtitle: state.selected == nil ? "Choose format" : "Drop to convert")
    }
}

/// The artwork must never steal native label clicks or Finder drag destinations.
private final class WheelArtworkHost: NSHostingView<LiveWheelArtwork> {
    override var isOpaque: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
