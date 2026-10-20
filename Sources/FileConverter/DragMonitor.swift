import AppKit
import CoreGraphics
import ConverterCore

@MainActor final class DragMonitor {
    var modifier = "shift"
    private var timer: Timer?
    private var state = DragGestureState()
    private let pasteboard = NSPasteboard(name: .drag)
    var onActivation: (([URL], NSPoint) -> Void)?
    var onRelease: ((NSPoint) -> Void)?
    var onDismissal: (() -> Void)?
    func start() {
        guard timer == nil else { return }
        state = DragGestureState()
        let timer = Timer(timeInterval: 0.025, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.sample() }
        }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }
    func stop() { timer?.invalidate(); timer = nil; state = DragGestureState(); onDismissal?() }
    private func sample() {
        let position = NSEvent.mouseLocation
        let down = CGEventSource.buttonState(.combinedSessionState, button: .left)
        let flags = CGEventSource.flagsState(.combinedSessionState)
        let expected: CGEventFlags = modifier == "option" ? .maskAlternate : modifier == "control" ? .maskControl : .maskShift
        let shift = flags.intersection([.maskShift,.maskCommand,.maskControl,.maskAlternate]) == expected
        let hasFiles = pasteboard.availableType(from: [.fileURL]) != nil
        let sample = DragSample(mouseDown: down, shiftDown: shift,
                                escapeDown: CGEventSource.keyState(.combinedSessionState, key: 53),
                                x: position.x, y: position.y, pasteboardRevision: pasteboard.changeCount, hasFiles: hasFiles)
        switch state.update(sample) {
        case .showWheel:
            let urls = Self.files(from: pasteboard)
            if !urls.isEmpty { onActivation?(urls, position) }
        case .releaseWheel:
            onRelease?(position)
        case .dismissWheel:
            onDismissal?()
        case nil: break
        }
    }
    static func files(from pasteboard: NSPasteboard) -> [URL] {
        pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
    }
}
