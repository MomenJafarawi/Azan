import AppKit
import SwiftUI

enum DeskSize: String, CaseIterable, Codable {
    case small, medium, large
    var arabic: String { switch self { case .small: return "صغير"; case .medium: return "متوسط"; case .large: return "كبير" } }
    var size: CGSize {
        switch self {
        case .small: return CGSize(width: 230, height: 230)
        case .medium: return CGSize(width: 470, height: 240)
        case .large: return CGSize(width: 470, height: 480)
        }
    }
}

/// Live animated sky drawn with Core Animation (runs on the GPU, almost no CPU):
/// gradient from the real sun height, twinkling stars, drifting clouds, sun/moon on its path.
struct LiveSky: NSViewRepresentable {
    var lat: Double
    var lon: Double
    var paused: Bool
    /// limit the sun/moon to the top part (points); nil = whole height
    var orbBand: CGFloat? = nil
    var orbOpacity: Float = 1
    /// horizontal place of the moon as a share of the width (nil = top-left corner)
    var orbX: CGFloat? = nil

    func makeNSView(context: Context) -> LiveSkyView { LiveSkyView() }
    func updateNSView(_ v: LiveSkyView, context: Context) {
        v.lat = lat; v.lon = lon; v.orbBand = orbBand
        v.orbOpacity = orbOpacity
        if v.orbX != orbX { v.orbX = orbX; v.rebuild() }
        v.setPaused(paused)
        v.refresh()
    }
}

final class LiveSkyView: NSView {
    var lat = 0.0, lon = 0.0
    var orbBand: CGFloat?
    var orbOpacity: Float = 1
    var orbX: CGFloat?
    func rebuild() { built = false; refresh() }
    private let sky = CAGradientLayer()
    private let warm = CAGradientLayer()
    private let starsLayer = CALayer()
    private let moonGlow = CAGradientLayer()
    private let moon = CAShapeLayer()
    private let meteor = CAGradientLayer()
    private var built = false
    private var lastSize = CGSize.zero

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer = CALayer()
        [sky, warm, starsLayer, moonGlow, moon, meteor].forEach { layer?.addSublayer($0) }
    }
    required init?(coder: NSCoder) { fatalError() }
    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()
        if bounds.size != lastSize { lastSize = bounds.size; built = false; refresh() }
    }

    func setPaused(_ p: Bool) {
        guard let l = layer else { return }
        if p && l.speed != 0 {
            let t = l.convertTime(CACurrentMediaTime(), from: nil)
            l.speed = 0; l.timeOffset = t
        } else if !p && l.speed == 0 {
            let paused = l.timeOffset
            l.speed = 1; l.timeOffset = 0; l.beginTime = 0
            l.beginTime = l.convertTime(CACurrentMediaTime(), from: nil) - paused
        }
    }

    private func cg(_ c: Color) -> CGColor { NSColor(c).cgColor }

    func refresh() {
        guard bounds.width > 0, !built else { return }
        built = true
        build(bounds.size)
    }

    private func build(_ size: CGSize) {
        CATransaction.begin(); CATransaction.setDisableActions(true)
        let look = SkyLook.luxury
        sky.frame = bounds
        sky.colors = [cg(look.top), cg(look.bottom)]
        sky.startPoint = CGPoint(x: 1, y: 0); sky.endPoint = CGPoint(x: 0, y: 1)

        // faint warm gold haze near the moon
        warm.type = .radial
        warm.frame = CGRect(x: -size.width * 0.3, y: -size.width * 0.3, width: size.width * 1.0, height: size.width * 1.0)
        warm.colors = [NSColor(red: 0.92, green: 0.76, blue: 0.40, alpha: 0.13).cgColor, NSColor.clear.cgColor]
        warm.startPoint = CGPoint(x: 0.5, y: 0.5); warm.endPoint = CGPoint(x: 1, y: 1)

        // crescent moon (top-left), gently breathing glow
        let band = min(size.height, orbBand ?? size.height)
        let r: CGFloat = 13
        let c = CGPoint(x: orbX.map { size.width * $0 } ?? 34, y: max(30, band * 0.35))
        let outer = CGPath(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2), transform: nil)
        let inner = CGPath(ellipseIn: CGRect(x: c.x - r + 6, y: c.y - r - 3, width: r * 2, height: r * 2), transform: nil)
        moon.path = outer
        let cutMask = CAShapeLayer()
        let mp = CGMutablePath(); mp.addRect(bounds.insetBy(dx: -50, dy: -50)); mp.addPath(inner)
        cutMask.path = mp
        cutMask.fillRule = .evenOdd
        moon.mask = cutMask
        moon.fillColor = NSColor(red: 0.97, green: 0.83, blue: 0.50, alpha: 1).cgColor
        moon.opacity = orbOpacity
        moon.shadowColor = NSColor(red: 1, green: 0.85, blue: 0.5, alpha: 1).cgColor
        moon.shadowRadius = 8; moon.shadowOpacity = 0.8; moon.shadowOffset = .zero
        moonGlow.type = .radial
        let gr = r * 4.5
        moonGlow.frame = CGRect(x: c.x - gr, y: c.y - gr, width: gr * 2, height: gr * 2)
        moonGlow.colors = [NSColor(red: 1, green: 0.85, blue: 0.5, alpha: 0.28).cgColor, NSColor.clear.cgColor]
        moonGlow.startPoint = CGPoint(x: 0.5, y: 0.5); moonGlow.endPoint = CGPoint(x: 1, y: 1)
        moonGlow.opacity = orbOpacity
        let breathe = CABasicAnimation(keyPath: "transform.scale")
        breathe.fromValue = 0.9; breathe.toValue = 1.12; breathe.duration = 4
        breathe.autoreverses = true; breathe.repeatCount = .infinity
        breathe.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        moonGlow.add(breathe, forKey: "breathe")

        // twinkling stars (a few golden ones)
        starsLayer.frame = bounds
        starsLayer.sublayers?.forEach { $0.removeFromSuperlayer() }
        var seed: UInt64 = 0x2545F4914F6CDD1D
        func rnd() -> CGFloat { seed ^= seed << 13; seed ^= seed >> 7; seed ^= seed << 17; return CGFloat(seed % 10_000) / 10_000 }
        let count = Int(size.width * size.height / 1500)
        for i in 0..<count {
            let s = CALayer()
            let d = 0.8 + rnd() * 2.0
            s.frame = CGRect(x: rnd() * size.width, y: rnd() * size.height, width: d, height: d)
            s.cornerRadius = d / 2
            s.backgroundColor = (i % 7 == 0 ? NSColor(red: 1, green: 0.86, blue: 0.55, alpha: 1) : NSColor.white).cgColor
            let a = CABasicAnimation(keyPath: "opacity")
            a.fromValue = 0.15; a.toValue = 0.95
            a.duration = 1.4 + Double(rnd()) * 3
            a.autoreverses = true; a.repeatCount = .infinity
            a.timeOffset = Double(rnd()) * 4
            s.add(a, forKey: "twinkle")
            starsLayer.addSublayer(s)
        }

        // a shooting star every ~14 seconds
        meteor.frame = CGRect(x: 0, y: 0, width: 70, height: 1.5)
        meteor.colors = [NSColor.white.withAlphaComponent(0).cgColor, NSColor.white.withAlphaComponent(0.9).cgColor]
        meteor.startPoint = CGPoint(x: 0, y: 0.5); meteor.endPoint = CGPoint(x: 1, y: 0.5)
        meteor.setAffineTransform(CGAffineTransform(rotationAngle: .pi * 0.12))
        meteor.opacity = 0
        let move = CABasicAnimation(keyPath: "position")
        move.fromValue = NSValue(point: NSPoint(x: size.width * 0.35, y: size.height * 0.08))
        move.toValue = NSValue(point: NSPoint(x: size.width * 0.85, y: size.height * 0.30))
        let fade = CAKeyframeAnimation(keyPath: "opacity")
        fade.values = [0, 0.9, 0]; fade.keyTimes = [0, 0.3, 1]
        let shot = CAAnimationGroup()
        shot.animations = [move, fade]
        shot.duration = 0.9
        let loop = CAAnimationGroup()
        loop.animations = [shot]
        loop.duration = 14
        loop.repeatCount = .infinity
        loop.timeOffset = 6
        meteor.add(loop, forKey: "meteor")
        CATransaction.commit()
    }
}

struct DeskWidgetView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var state: DeskState

    var body: some View {
        let look = model.sky
        let size = model.settings.deskSize
        let base = size.size
        let s = CGFloat(state.liveScale ?? model.settings.deskScale)
        ZStack(alignment: .bottomTrailing) {
            if let lat = model.settings.latitude, let lon = model.settings.longitude {
                LiveSky(lat: lat, lon: lon, paused: !state.visible, orbBand: 60 * s, orbX: size == .small ? 0.12 : 0.56)
            } else {
                SkyBackground(look: look)
            }
            Veil(look: look)
            inner(look, size)
                .foregroundStyle(look.text)
                .environment(\.layoutDirection, .rightToLeft)
                .environment(\.locale, Fmt.locale(latin: model.latin))
                .frame(width: base.width, height: base.height)
                .scaleEffect(s, anchor: .topLeading)
                .frame(width: base.width * s, height: base.height * s, alignment: .topLeading)
            // resize handle: drag this corner to make the widget bigger or smaller
            Image(systemName: "arrow.up.left.and.arrow.down.right")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(look.gold.opacity(0.55))
                .padding(9)
                .help("اسحب أي طرف لتكبير أو تصغير الويدجت")
        }
        .environment(\.layoutDirection, .leftToRight)
        .frame(width: base.width * s, height: base.height * s)
        .clipShape(RoundedRectangle(cornerRadius: 28 * s, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 28 * s, style: .continuous).strokeBorder(look.gold.opacity(0.55), lineWidth: 1))
    }

    @ViewBuilder private func inner(_ look: SkyLook, _ size: DeskSize) -> some View {
        Group {
            if model.input == nil {
                Text("افتح الإعدادات واختار مدينتك").font(AppFont.naskh(16)).padding()
            } else {
                switch size {
                case .small: nextBlock(look).padding(22)
                case .medium:
                    HStack(spacing: 14) {
                        nextBlock(look)
                        Rectangle().fill(look.text.opacity(0.15)).frame(width: 0.7)
                        list(look)
                    }.padding(22)
                case .large:
                    VStack(spacing: 12) {
                        HStack(spacing: 14) {
                            nextBlock(look)
                            Rectangle().fill(look.text.opacity(0.15)).frame(width: 0.7)
                            list(look)
                        }
                        khatma(look)
                    }.padding(22)
                }
            }
        }
    }

    private func nextBlock(_ look: SkyLook) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: "location.fill").font(.system(size: 9))
                Text(model.settings.placeName).font(.system(size: 13, weight: .medium)).lineLimit(1)
                Spacer(minLength: 0)
            }
            .foregroundStyle(look.secondary)
            Text(Fmt.hijri(model.now, offset: model.settings.hijriOffset, latin: model.latin, withYear: false))
                .font(AppFont.naskh(15, bold: true)).foregroundStyle(look.secondary)
            Spacer(minLength: 0)
            if let (p, t) = model.next {
                Text(p == .maghrib && model.ramadan ? "الإفطار" : p.arabic).font(AppFont.naskh(38, bold: true))
                    .foregroundStyle(look.gold)
                    .shadow(color: look.gold.opacity(0.35), radius: 8)
                if model.playing != nil {
                    Label("الأذان شغّال · اكبس للإيقاف", systemImage: "speaker.wave.2.fill")
                        .font(.system(size: 13, weight: .bold))
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Capsule().fill(look.gold)).foregroundStyle(Color(red: 0.08, green: 0.09, blue: 0.2))
                } else {
                    Text(Fmt.countdownLong(t.timeIntervalSince(model.now), latin: model.latin))
                        .font(.system(size: 15, weight: .semibold, design: .rounded)).foregroundStyle(look.text)
                }
                GoldBar(value: model.progress, look: look).padding(.top, 2)
                Text("الأذان \(Fmt.time(t, latin: model.latin, use24h: model.settings.use24h))").font(.system(size: 13, weight: .medium)).foregroundStyle(look.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func list(_ look: SkyLook) -> some View {
        let day = model.today
        let next = model.next
        let nextToday = next.map { Calendar.current.isDate($0.1, inSameDayAs: model.now) } ?? false
        return VStack(spacing: 3) {
            ForEach(Prayer.allCases, id: \.self) { q in
                let hl = q == next?.0 && nextToday
                HStack {
                    Text(q.arabic).font(AppFont.naskh(17, bold: hl))
                    Spacer()
                    if let tt = day?.times[q] {
                        Text(Fmt.time(tt, latin: model.latin, use24h: model.settings.use24h))
                            .font(.system(size: 15, weight: hl ? .bold : .medium, design: .rounded).monospacedDigit())
                    }
                }
                .padding(.horizontal, 9).padding(.vertical, 3)
                .background(RoundedRectangle(cornerRadius: 9).fill(hl ? look.gold.opacity(0.20) : .clear))
                .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(hl ? look.gold.opacity(0.7) : .clear, lineWidth: 1))
                .opacity(!hl && (day?.times[q].map { $0 < model.now } ?? false) ? 0.6 : 1)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func khatma(_ look: SkyLook) -> some View {
        let k = model.settings.khatma
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("وردي", systemImage: "book.closed.fill").font(AppFont.naskh(18, bold: true))
                Spacer()
                Text("\(Fmt.num(k.lastRead, latin: model.latin)) / \(Fmt.num(Quran.pages, latin: model.latin))").font(.system(size: 13, weight: .semibold, design: .rounded).monospacedDigit())
            }
            GoldBar(value: Double(k.lastRead) / Double(Quran.pages), look: look)
            if let r = k.nextPortion(model.now) {
                HStack {
                    Text("صفحة \(Fmt.num(r.lowerBound, latin: model.latin))–\(Fmt.num(r.upperBound, latin: model.latin)) · \(Quran.surah(onPage: r.lowerBound))")
                        .font(.system(size: 13, weight: .medium))
                    Spacer()
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .glass(look, radius: 16)
    }
}

final class DeskState: ObservableObject {
    @Published var visible = true
    /// size while the corner is being dragged (saved to settings on release)
    @Published var liveScale: Double? = nil
}

/// Borderless window that lives on the desktop; drag it anywhere, position is remembered.
final class DeskWidgetController: NSObject, NSWindowDelegate {
    let model: AppModel
    let state = DeskState()
    private var panel: NSPanel?
    var onOpenSettings: (() -> Void)?
    var onClick: (() -> Void)?

    init(model: AppModel) { self.model = model }

    func apply() {
        guard model.settings.deskOn else { panel?.orderOut(nil); panel = nil; return }
        let base = model.settings.deskSize.size
        let sc = CGFloat(model.settings.deskScale)
        let sz = CGSize(width: base.width * sc, height: base.height * sc)
        let p = panel ?? makePanel()
        p.level = model.settings.deskOnTop ? .floating : NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
        var f = p.frame
        f.origin.y += f.height - sz.height   // keep the top edge in place when resizing
        f.size = sz
        p.setFrame(f, display: true)
        p.orderFrontRegardless()
        panel = p
    }

    private func makePanel() -> NSPanel {
        let sz = model.settings.deskSize.size
        let p = NSPanel(contentRect: NSRect(origin: .zero, size: sz), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.isMovableByWindowBackground = false
        p.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        p.delegate = self
        let host = DeskHostingView(rootView: DeskWidgetView(model: model, state: state))
        host.onClick = { [weak self] in self?.onClick?() }
        host.onResize = { [weak self] factor, done, fromLeft in self?.resize(factor, done: done, fromLeft: fromLeft) }
        host.menu = makeMenu()
        p.contentView = host
        if let s = UserDefaults.standard.string(forKey: "deskOrigin") {
            p.setFrameOrigin(NSPointFromString(s))
        } else if let screen = NSScreen.main {
            let v = screen.visibleFrame
            p.setFrameOrigin(NSPoint(x: v.maxX - sz.width - 30, y: v.maxY - sz.height - 30))
        }
        // keep it on a visible screen
        if !NSScreen.screens.contains(where: { $0.frame.intersects(p.frame) }), let screen = NSScreen.main {
            p.setFrameOrigin(NSPoint(x: screen.visibleFrame.midX - sz.width / 2, y: screen.visibleFrame.midY))
        }
        return p
    }

    private func makeMenu() -> NSMenu {
        let m = NSMenu()
        for s in DeskSize.allCases {
            let it = NSMenuItem(title: "الحجم: \(s.arabic)", action: #selector(setSize(_:)), keyEquivalent: "")
            it.representedObject = s.rawValue; it.target = self
            m.addItem(it)
        }
        m.addItem(.separator())
        for (t, sel) in [("تكبير", #selector(bigger)), ("تصغير", #selector(smaller)), ("الحجم الأصلي", #selector(resetScale))] {
            let it = NSMenuItem(title: t, action: sel, keyEquivalent: ""); it.target = self; m.addItem(it)
        }
        m.addItem(.separator())
        let clock = NSMenuItem(title: "الساعة ٢٤", action: #selector(toggle24), keyEquivalent: ""); clock.target = self
        m.addItem(clock)
        m.addItem(.separator())
        let top = NSMenuItem(title: "فوق كل النوافذ", action: #selector(toggleTop), keyEquivalent: ""); top.target = self
        m.addItem(top)
        let st = NSMenuItem(title: "الإعدادات…", action: #selector(openSettings), keyEquivalent: ""); st.target = self
        m.addItem(st)
        let hide = NSMenuItem(title: "إخفاء الويدجت", action: #selector(hide), keyEquivalent: ""); hide.target = self
        m.addItem(hide)
        m.delegate = self
        return m
    }

    private var resizeStart: (scale: Double, top: CGFloat, left: CGFloat, right: CGFloat)?
    /// edge drag: factor = new width / width when the drag started; the top edge stays put,
    /// and the opposite side edge stays put
    func resize(_ factor: CGFloat, done: Bool, fromLeft: Bool = false) {
        guard let p = panel else { return }
        if resizeStart == nil { resizeStart = (model.settings.deskScale, p.frame.maxY, p.frame.minX, p.frame.maxX) }
        guard let st = resizeStart else { return }
        let sc = min(2, max(0.6, st.scale * Double(factor)))
        let base = model.settings.deskSize.size
        let w = base.width * sc, h = base.height * sc
        state.liveScale = sc
        p.setFrame(NSRect(x: fromLeft ? st.right - w : st.left, y: st.top - h, width: w, height: h), display: true)
        if done {
            resizeStart = nil
            state.liveScale = nil
            model.settings.deskScale = (sc * 100).rounded() / 100
            UserDefaults.standard.set(NSStringFromPoint(p.frame.origin), forKey: "deskOrigin")
        }
    }
    private func step(_ d: Double) {
        model.settings.deskScale = min(2, max(0.6, ((model.settings.deskScale + d) * 10).rounded() / 10))
    }
    @objc private func bigger() { step(0.1) }
    @objc private func smaller() { step(-0.1) }
    @objc private func resetScale() { model.settings.deskScale = 1 }
    @objc private func toggle24() { model.settings.use24h.toggle() }

    @objc private func setSize(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let s = DeskSize(rawValue: raw) else { return }
        model.settings.deskSize = s
    }
    @objc private func toggleTop() { model.settings.deskOnTop.toggle() }
    @objc private func hide() { model.settings.deskOn = false }
    @objc private func openSettings() { onOpenSettings?() }

    func windowDidMove(_ n: Notification) {
        if let p = panel { UserDefaults.standard.set(NSStringFromPoint(p.frame.origin), forKey: "deskOrigin") }
    }
    func windowDidChangeOcclusionState(_ n: Notification) {
        state.visible = panel?.occlusionState.contains(.visible) ?? true
    }
}

extension DeskWidgetController: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        for it in menu.items {
            if let raw = it.representedObject as? String { it.state = raw == model.settings.deskSize.rawValue ? .on : .off }
            if it.action == #selector(toggleTop) { it.state = model.settings.deskOnTop ? .on : .off }
            if it.action == #selector(toggle24) { it.title = model.settings.use24h ? "الساعة: ٢٤ (اكبس لـ١٢)" : "الساعة: ١٢ (اكبس لـ٢٤)" }
        }
    }
}

/// Click = open the app, drag = move the widget.
final class DeskHostingView<V: View>: NSHostingView<V> {
    var onClick: (() -> Void)?
    /// factor, finished, anchor on the right edge (left edge dragged)
    var onResize: ((CGFloat, Bool, Bool) -> Void)?
    private var start: NSPoint?
    private var origin: NSPoint?
    private var startSize = CGSize(width: 1, height: 1)
    private var dragged = false
    private var edge: Edge = .none

    override func resetCursorRects() { EdgeZones.addCursorRects(to: self) }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with e: NSEvent) {
        start = NSEvent.mouseLocation
        origin = window?.frame.origin
        startSize = window?.frame.size ?? CGSize(width: 1, height: 1)
        dragged = false
        // edges and bottom corners resize; the handle icon corner too
        let p = e.locationInWindow
        edge = EdgeZones.edge(at: p, size: startSize)
        if edge == .none && p.x > startSize.width - 34 && p.y < 34 { edge = .bottomRight }
    }
    private func factor(_ now: NSPoint) -> CGFloat {
        guard let s = start else { return 1 }
        let g = EdgeZones.grow(edge, dx: now.x - s.x, dy: now.y - s.y, aspect: startSize.width / startSize.height)
        return max(0.2, (startSize.width + g) / startSize.width)
    }
    override func mouseDragged(with e: NSEvent) {
        guard let s = start, let o = origin, let w = window else { return }
        let now = NSEvent.mouseLocation
        let dx = now.x - s.x, dy = now.y - s.y
        if !dragged && hypot(dx, dy) < 4 { return }
        dragged = true
        if edge != .none {
            onResize?(factor(now), false, edge == .left || edge == .bottomLeft)
        } else {
            w.setFrameOrigin(NSPoint(x: o.x + dx, y: o.y + dy))
        }
    }
    override func mouseUp(with e: NSEvent) {
        if edge != .none && dragged {
            onResize?(factor(NSEvent.mouseLocation), true, edge == .left || edge == .bottomLeft)
        } else if !dragged { onClick?() }
        start = nil; origin = nil; dragged = false; edge = .none
    }
}
