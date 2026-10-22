import AppKit
import SwiftUI

/// The window that opens under the menu bar icon: one rounded card, always fully on screen.
final class KeyPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override func cancelOperation(_ sender: Any?) { orderOut(nil) }
}

final class MenuPanelController: NSObject, NSWindowDelegate {
    private let model: AppModel
    private var panel: KeyPanel?
    private var host: DraggableHostingView<MainView>?
    private var clickMonitor: Any?
    /// true after the user drags the window: it then stays until closed with ×
    private var pinned = false
    private var positioning = false
    var openSettings: () -> Void = {}
    var openAdhkar: (AdhkarKind) -> Void = { _ in }
    var isShown: Bool { panel?.isVisible ?? false }

    init(model: AppModel) { self.model = model }

    private weak var lastButton: NSStatusBarButton?

    private func makeView(visible: Bool, maxHeight: CGFloat, scroll: CGFloat? = nil, natural: CGFloat? = nil) -> MainView {
        MainView(model: model, visible: visible, maxHeight: maxHeight, scrollHeight: scroll,
                 openSettings: { [weak self] in self?.close(); self?.openSettings() },
                 openAdhkar: { [weak self] k in self?.close(); self?.openAdhkar(k) },
                 quit: { NSApp.terminate(nil) },
                 close: { [weak self] in self?.close(force: true) },
                 naturalHeight: natural, relayout: { [weak self] in self?.relayout() })
    }

    func toggle(from button: NSStatusBarButton) {
        if isShown { close(force: true) } else { show(from: button) }
    }

    func show(from button: NSStatusBarButton) {
        guard let bw = button.window else { return }
        let screen = bw.screen ?? NSScreen.main!
        let vis = screen.visibleFrame
        let gap: CGFloat = 8, margin: CGFloat = 12
        let maxH = vis.height - gap - margin
        model.now = Date()
        pinned = false
        positioning = true

        let p = panel ?? makePanel()
        // measure the natural height first, scroll only if the screen is too short
        lastButton = button
        let (size, view) = measured(maxH: maxH)
        let h = host ?? DraggableHostingView(rootView: view)
        h.onResize = { [weak self] f, done, fromLeft in self?.edgeResize(f, done: done, fromLeft: fromLeft) }
        h.rootView = view
        if host == nil { p.contentView = h; host = h }

        // centred under the icon, clamped inside the screen
        let iconFrame = bw.frame
        var x = iconFrame.midX - size.width / 2
        x = min(max(x, vis.minX + margin), vis.maxX - size.width - margin)
        let y = vis.maxY - gap - size.height
        p.setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: true)

        p.level = .popUpMenu
        p.alphaValue = 0
        p.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        let end = p.frame
        p.setFrame(end.offsetBy(dx: 0, dy: 8), display: false)
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.18
            p.animator().alphaValue = 1
            p.animator().setFrame(end, display: true)
        }, completionHandler: { [weak self] in self?.positioning = false })
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in self?.close() }
    }

    /// closes unless the user pinned the window by moving it (force = the × button / icon)
    /// natural height at scale 1, then the window size at the chosen scale
    private func measured(maxH: CGFloat) -> (NSSize, MainView) {
        let measure = NSHostingView(rootView: makeView(visible: false, maxHeight: maxH))
        let natural = measure.fittingSize.height
        let s = CGFloat(model.settings.panelScale)
        let total = natural * s
        let fits = total <= maxH
        let size = NSSize(width: MainView.width * s, height: fits ? total : maxH)
        return (size, makeView(visible: true, maxHeight: maxH, scroll: fits ? nil : maxH, natural: natural))
    }

    private var dragStart: (scale: Double, top: CGFloat, left: CGFloat, right: CGFloat, natural: CGFloat)?
    /// edge drag on the main window: everything scales together (0.8 ... 1.5)
    func edgeResize(_ factor: CGFloat, done: Bool, fromLeft: Bool) {
        guard let p = panel, let h = host else { return }
        if dragStart == nil {
            let natural = h.rootView.naturalHeight ?? (p.frame.height / CGFloat(model.settings.panelScale))
            dragStart = (model.settings.panelScale, p.frame.maxY, p.frame.minX, p.frame.maxX, natural)
        }
        guard let st = dragStart else { return }
        let sc = min(1.5, max(0.8, st.scale * Double(factor)))
        let vis = (p.screen ?? NSScreen.main!).visibleFrame
        let w = MainView.width * CGFloat(sc), hgt = min(st.natural * CGFloat(sc), vis.height - 20)
        PanelUI.shared.liveScale = sc
        positioning = true
        p.setFrame(NSRect(x: fromLeft ? st.right - w : st.left, y: st.top - hgt, width: w, height: hgt), display: true)
        if done {
            dragStart = nil
            model.settings.panelScale = (sc * 100).rounded() / 100
            PanelUI.shared.liveScale = nil
            pinned = true
            relayout()
        }
    }

    /// after A− / A+: resize in place, keeping the top edge where it is
    func relayout() {
        guard let p = panel, p.isVisible, let h = host else { return }
        let vis = (p.screen ?? NSScreen.main!).visibleFrame
        let (size, view) = measured(maxH: vis.height - 20)
        positioning = true
        h.rootView = view
        var f = p.frame
        let top = f.maxY
        var x = f.midX - size.width / 2
        x = min(max(x, vis.minX + 12), vis.maxX - size.width - 12)
        f = NSRect(x: x, y: top - size.height, width: size.width, height: size.height)
        p.setFrame(f, display: true, animate: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in self?.positioning = false }
    }

    func close(force: Bool = false) {
        if pinned && !force { return }
        pinned = false
        if let m = clickMonitor { NSEvent.removeMonitor(m); clickMonitor = nil }
        guard let p = panel, p.isVisible else { return }
        host?.rootView = makeView(visible: false, maxHeight: p.frame.height, scroll: host?.rootView.scrollHeight, natural: host?.rootView.naturalHeight)
        NSAnimationContext.runAnimationGroup({ $0.duration = 0.12; p.animator().alphaValue = 0 }, completionHandler: { p.orderOut(nil) })
    }

    private func makePanel() -> KeyPanel {
        let p = KeyPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.level = .popUpMenu
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        p.delegate = self
        p.hidesOnDeactivate = false
        panel = p
        return p
    }

    func windowDidResignKey(_ n: Notification) { close() }

    func windowDidMove(_ n: Notification) {
        guard !positioning, NSEvent.pressedMouseButtons != 0, !pinned else { return }
        pinned = true
        if let m = clickMonitor { NSEvent.removeMonitor(m); clickMonitor = nil }
        panel?.level = .floating
    }
}

/// Lets the window be dragged from any spot while SwiftUI buttons keep working:
/// a press that moves more than a few points drags the window, a still click goes to SwiftUI.
final class DraggableHostingView<V: View>: NSHostingView<V> {
    var onResize: ((CGFloat, Bool, Bool) -> Void)?
    private var start: NSPoint?
    private var origin: NSPoint?
    private var dragging = false
    private var edge: Edge = .none
    private var startSize = CGSize(width: 1, height: 1)

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func resetCursorRects() { EdgeZones.addCursorRects(to: self) }

    override func mouseDown(with e: NSEvent) {
        start = NSEvent.mouseLocation
        origin = window?.frame.origin
        startSize = window?.frame.size ?? startSize
        dragging = false
        edge = EdgeZones.edge(at: e.locationInWindow, size: startSize)
        if edge != .none { return }     // edge = resize, not a click
        super.mouseDown(with: e)
    }
    private func factor(_ now: NSPoint) -> CGFloat {
        guard let s = start else { return 1 }
        // height follows the content, so the width decides the scale
        let g = EdgeZones.grow(edge, dx: now.x - s.x, dy: now.y - s.y, aspect: 1)
        return max(0.2, (startSize.width + g) / startSize.width)
    }
    override func mouseDragged(with e: NSEvent) {
        if edge != .none {
            onResize?(factor(NSEvent.mouseLocation), false, edge == .left || edge == .bottomLeft)
            return
        }
        if let s = start, let o = origin, let w = window {
            let now = NSEvent.mouseLocation
            let dx = now.x - s.x, dy = now.y - s.y
            if dragging || hypot(dx, dy) > 4 {
                dragging = true
                w.setFrameOrigin(NSPoint(x: o.x + dx, y: o.y + dy))
                return
            }
        }
        super.mouseDragged(with: e)
    }
    override func mouseUp(with e: NSEvent) {
        if edge != .none {
            onResize?(factor(NSEvent.mouseLocation), true, edge == .left || edge == .bottomLeft)
            start = nil; origin = nil; edge = .none
            return
        }
        start = nil; origin = nil
        let wasDragging = dragging
        dragging = false
        super.mouseUp(with: e)
        _ = wasDragging
    }
}
