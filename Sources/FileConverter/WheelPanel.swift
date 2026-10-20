import AppKit
import SwiftUI
import ConverterCore

@MainActor final class WheelPanelController {
    private(set) var panel: NSPanel?
    var inspect: (([URL]) async throws -> [AssetDescriptor])?
    var installedPacks: Set<String> = []
    private var inspection: Task<Void,Never>?
    private var pointerTimer: Timer?
    private var dragPresentation = false
    private var generation = UUID()
    var onConversion: (([URL], WheelChoice) -> Void)?
    func show(sources: [URL], at point: NSPoint, clickable: Bool = false) {
        dismiss()
        dragPresentation = !clickable
        let id = UUID(); generation = id
        inspection = Task { [weak self] in
            guard let self, let inspect, let assets = try? await inspect(sources), !Task.isCancelled, generation == id else { return }
            let formats = WheelChoice.common(assets,installedPacks:installedPacks)
            guard !formats.isEmpty else { return }
            present(sources:sources,formats:formats,at:point,clickable:clickable)
        }
    }
    private func present(sources: [URL], formats: [WheelChoice], at point: NSPoint, clickable: Bool) {
        let size = NSSize(width: 420, height: 420)
        let screen = NSScreen.screens.first(where: { $0.frame.contains(point) }) ?? NSScreen.main
        let bounds = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let origin = NSPoint(x: min(max(point.x - 210, bounds.minX), bounds.maxX - size.width),
                             y: min(max(point.y - 210, bounds.minY), bounds.maxY - size.height))
        let panel = WheelPanel(contentRect: NSRect(origin: origin, size: size), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        // A zero-alpha window can pass Finder's drop through while SwiftUI's
        // glass is compositing. Keep an imperceptible native hit surface.
        panel.backgroundColor = NSColor.black.withAlphaComponent(0.001)
        panel.isOpaque = false; panel.hasShadow = false
        panel.hidesOnDeactivate = false; panel.isReleasedWhenClosed = false
        panel.acceptsMouseMovedEvents = true
        let wheel = WheelView(frame: NSRect(origin: .zero, size: size), sources: sources, formats: formats)
        wheel.onChoose = { [weak self] selectedSources, format in
            self?.dismiss(); self?.onConversion?(selectedSources, format)
        }
        wheel.onCancel = { [weak self] in self?.dismiss() }
        panel.contentView = wheel; self.panel = panel
        dragPresentation = !clickable
        panel.orderFrontRegardless()
        if clickable {
            panel.makeKey(); panel.makeFirstResponder(wheel)
        } else {
            // Finder owns the drag session. Its destination callbacks can be
            // coalesced, so keep the visual selection in sync independently.
            wheel.updateDragHighlight(at: NSEvent.mouseLocation)
            let timer = Timer(timeInterval: 1.0 / 120, repeats: true) { [weak wheel] _ in
                MainActor.assumeIsolated {
                    // DragMonitor coordinates release with the native drop callback.
                    guard CGEventSource.buttonState(.combinedSessionState, button: .left) else { return }
                    wheel?.updateDragHighlight(at: NSEvent.mouseLocation)
                }
            }
            timer.tolerance = 0.002
            pointerTimer = timer
            RunLoop.main.add(timer, forMode: .common)
        }
    }
    func releaseDrag(at screenPoint: NSPoint) {
        pointerTimer?.invalidate(); pointerTimer = nil
        guard dragPresentation, let panel, let wheel = panel.contentView as? WheelView else {
            if dragPresentation { dismiss() }
            return
        }
        // A covered wheel must never convert a drop intended for another window.
        let overWheel = NSWindow.windowNumber(at: screenPoint, belowWindowWithWindowNumber: 0) == panel.windowNumber
        let id = generation
        // Let AppKit consume the drop first. If Finder omits the destination
        // callback, commit the same captured release position once it settles.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self, weak wheel] in
            guard let self, self.generation == id else { return }
            if overWheel { wheel?.completeDrag(at: screenPoint) }
            if self.generation == id { self.dismiss() }
        }
    }
    func dismiss() {
        pointerTimer?.invalidate(); pointerTimer = nil
        dragPresentation = false
        inspection?.cancel(); inspection = nil; generation = UUID(); panel?.orderOut(nil); panel = nil
    }
}

private final class WheelPanel: NSPanel { override var canBecomeKey: Bool { true } }

@MainActor final class WheelView: NSView {
    let sources: [URL]
    let formats: [WheelChoice]
    var selected: Int? {
        didSet {
            guard selected != oldValue else { return }
            artworkState.selected = selected
            updateButtons()
        }
    }
    var onChoose: (([URL], WheelChoice) -> Void)?
    var onCancel: (() -> Void)?
    private let artworkState = WheelArtworkState()
    private var labelButtons: [NSButton] = []
    private var tracking: NSTrackingArea?
    private var didChoose = false
    private var geometry: WheelGeometry { WheelGeometry(count: formats.count) }
    override var acceptsFirstResponder: Bool { true }
    init(frame: NSRect, sources: [URL], formats: [WheelChoice]) {
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
            button.toolTip = "\(format.title) for \(sources.count) files"
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
    func updateDragHighlight(at screenPoint: NSPoint) {
        guard let window else { return }
        selected = index(at: convert(window.convertPoint(fromScreen: screenPoint), from: nil))
    }
    func completeDrag(at screenPoint: NSPoint) {
        updateDragHighlight(at: screenPoint)
        chooseSelected(sources)
    }
    @discardableResult private func chooseSelected(_ urls: [URL]) -> Bool {
        guard !didChoose, let selected else { return false }
        didChoose = true
        onChoose?(urls, formats[selected])
        return true
    }
    override func mouseMoved(with event: NSEvent) { selected = index(at: convert(event.locationInWindow, from: nil)) }
    override func mouseExited(with event: NSEvent) { selected = nil }
    override func mouseDown(with event: NSEvent) {
        if let index = index(at: convert(event.locationInWindow, from: nil)) { selected = index; chooseSelected(sources) }
        else { onCancel?() }
    }
    @objc private func chooseLabel(_ sender: NSButton) { selected = sender.tag; chooseSelected(sources) }
    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53: onCancel?()
        case 123, 126: selected = ((selected ?? 0) - 1 + formats.count) % formats.count
        case 124, 125: selected = ((selected ?? -1) + 1) % formats.count
        case 36, 76: chooseSelected(sources)
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
        // Resolve the final drop independently of the last hover sample.
        selected = index(at: convert(sender.draggingLocation, from: nil))
        guard selected != nil, DragMonitor.files(from: sender.draggingPasteboard) == sources else { return false }
        let urls = DragMonitor.files(from: sender.draggingPasteboard)
        return chooseSelected(urls)
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
    let formats: [WheelChoice]

    var body: some View {
        WheelArtwork(labels: formats.map(\.title), selected: state.selected,
                     title: state.selected.map { formats[$0].title }
                        ?? (sources.count == 1 ? sources[0].pathExtension.uppercased() : "\(sources.count) FILES"),
                     subtitle: state.selected == nil ? "Choose format" : "Drop to convert", animatesSelection: false)
    }
}

/// The artwork must never steal native label clicks or Finder drag destinations.
private final class WheelArtworkHost: NSHostingView<LiveWheelArtwork> {
    override var isOpaque: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
