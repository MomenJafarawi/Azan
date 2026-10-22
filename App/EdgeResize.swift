import AppKit

/// Shared edge-drag logic: the left, right and bottom edges and the bottom corners resize a window
/// proportionally (everything inside scales together, so text and numbers keep their proportions).
enum Edge { case none, left, right, bottom, bottomLeft, bottomRight }

struct EdgeZones {
    static let band: CGFloat = 10
    /// p = point in window coordinates (origin bottom-left)
    static func edge(at p: NSPoint, size: CGSize) -> Edge {
        let l = p.x < band + 6, r = p.x > size.width - band - 6, b = p.y < band + 6
        if b && l { return .bottomLeft }
        if b && r { return .bottomRight }
        if p.x < band { return .left }
        if p.x > size.width - band { return .right }
        if p.y < band { return .bottom }
        return .none
    }
    /// growth in points for a drag of (dx, dy) on that edge (dy is screen-up positive)
    static func grow(_ e: Edge, dx: CGFloat, dy: CGFloat, aspect: CGFloat) -> CGFloat {
        switch e {
        case .right: return dx
        case .left: return -dx
        case .bottom: return -dy * aspect
        case .bottomRight: return max(dx, -dy * aspect)
        case .bottomLeft: return max(-dx, -dy * aspect)
        case .none: return 0
        }
    }
    static func cursor(_ e: Edge) -> NSCursor {
        if #available(macOS 15.0, *) {
            switch e {
            case .left, .right: return .columnResize(directions: .all)
            case .bottom: return .rowResize(directions: .all)
            case .bottomLeft: return .frameResize(position: .bottomLeft, directions: .all)
            case .bottomRight: return .frameResize(position: .bottomRight, directions: .all)
            case .none: return .arrow
            }
        }
        switch e {
        case .left, .right: return .resizeLeftRight
        case .bottom: return .resizeUpDown
        case .bottomLeft, .bottomRight: return .crosshair
        case .none: return .arrow
        }
    }
    /// cursor rects for a view (handles flipped views)
    static func addCursorRects(to v: NSView) {
        let w = v.bounds.width, h = v.bounds.height, k = band
        let bottomY = v.isFlipped ? h - k : 0
        v.addCursorRect(NSRect(x: 0, y: 0, width: k, height: h), cursor: cursor(.left))
        v.addCursorRect(NSRect(x: w - k, y: 0, width: k, height: h), cursor: cursor(.right))
        v.addCursorRect(NSRect(x: k, y: bottomY, width: w - 2 * k, height: k), cursor: cursor(.bottom))
        v.addCursorRect(NSRect(x: 0, y: v.isFlipped ? h - k - 6 : 0, width: k + 6, height: k + 6), cursor: cursor(.bottomLeft))
        v.addCursorRect(NSRect(x: w - k - 6, y: v.isFlipped ? h - k - 6 : 0, width: k + 6, height: k + 6), cursor: cursor(.bottomRight))
    }
}
