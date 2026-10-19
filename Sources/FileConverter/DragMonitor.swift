import AppKit
import CoreGraphics
import ConverterCore

@MainActor final class DragMonitor {
    private var timer: Timer?
    private var state = DragGestureState()
    private let pasteboard = NSPasteboard(name: .drag)
    var onActivation: (([URL], NSPoint) -> Void)?
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
        let shift = flags.contains(.maskShift) && flags.intersection([.maskCommand, .maskControl, .maskAlternate]).isEmpty
        let hasFiles = pasteboard.availableType(from: [.fileURL]) != nil
        let sample = DragSample(mouseDown: down, shiftDown: shift,
                                escapeDown: down && CGEventSource.keyState(.combinedSessionState, key: 53),
                                x: position.x, y: position.y, pasteboardRevision: pasteboard.changeCount, hasFiles: hasFiles)
        switch state.update(sample) {
        case .showWheel:
            let urls = Self.files(from: pasteboard)
            if !urls.isEmpty { onActivation?(urls, position) }
        case .dismissWheel:
            // AppKit's drop callback must finish before the polling cleanup.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in self?.onDismissal?() }
        case nil: break
        }
    }
    static func files(from pasteboard: NSPasteboard) -> [URL] {
        pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
    }
}
