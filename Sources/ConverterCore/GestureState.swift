import Foundation

public struct DragSample: Sendable {
    public var mouseDown: Bool
    public var shiftDown: Bool
    public var escapeDown: Bool
    public var x: Double
    public var y: Double
    public var pasteboardRevision: Int
    public var hasFiles: Bool
    public init(mouseDown: Bool, shiftDown: Bool, escapeDown: Bool = false, x: Double, y: Double, pasteboardRevision: Int, hasFiles: Bool) {
        self.mouseDown = mouseDown; self.shiftDown = shiftDown; self.escapeDown = escapeDown
        self.x = x; self.y = y; self.pasteboardRevision = pasteboardRevision; self.hasFiles = hasFiles
    }
}

public struct DragGestureState: Sendable {
    public enum Action: Equatable { case showWheel, releaseWheel, dismissWheel }
    private var previousDown = false
    private var idleRevision: Int?
    private var dragRevision: Int?
    private var startX = 0.0
    private var startY = 0.0
    private var activated = false
    private var cancelled = false
    public init() {}
    public mutating func update(_ sample: DragSample) -> Action? {
        if !sample.mouseDown {
            let shouldRelease = activated && !cancelled && !sample.escapeDown
            let shouldDismiss = activated && !shouldRelease
            previousDown = false; activated = false; cancelled = false
            idleRevision = sample.pasteboardRevision; dragRevision = nil
            return shouldRelease ? .releaseWheel : shouldDismiss ? .dismissWheel : nil
        }
        if !previousDown {
            previousDown = true; startX = sample.x; startY = sample.y
            dragRevision = idleRevision ?? sample.pasteboardRevision
        }
        if sample.escapeDown {
            cancelled = true
            if activated { activated = false; return .dismissWheel }
        }
        guard !activated, !cancelled, sample.shiftDown, sample.hasFiles,
              sample.pasteboardRevision != dragRevision,
              hypot(sample.x - startX, sample.y - startY) >= 6 else { return nil }
        activated = true
        return .showWheel
    }
}

public struct WheelGeometry: Sendable {
    public let count: Int
    public let innerRadius: Double
    public let outerRadius: Double
    public let angularGap: Double
    public init(count: Int, innerRadius: Double = 62, outerRadius: Double = 186, angularGap: Double = 0.07) {
        self.count = count; self.innerRadius = innerRadius; self.outerRadius = outerRadius; self.angularGap = angularGap
    }
    /// Coordinates relative to the wheel centre, in AppKit's y-up space.
    public func sector(x: Double, y: Double) -> Int? {
        guard count > 0 else { return nil }
        let radius = hypot(x, y)
        guard radius >= innerRadius, radius <= outerRadius else { return nil }
        let step = 2 * Double.pi / Double(count)
        let clockwise = (atan2(x, y) + 2 * Double.pi).truncatingRemainder(dividingBy: 2 * Double.pi)
        let index = Int((clockwise / step).rounded()) % count
        let centre = Double(index) * step
        let difference = abs(atan2(sin(clockwise - centre), cos(clockwise - centre)))
        return difference <= step / 2 - angularGap / 2 ? index : nil
    }
}
