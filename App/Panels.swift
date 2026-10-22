import AppKit
import SwiftUI

/// Floating card in the top corner (instead of system notifications, so it can carry the living sky).
final class FloatingPanel {
    private var panel: NSPanel?
    private var closeWork: DispatchWorkItem?

    func show<V: View>(_ view: V, autoClose: TimeInterval?) {
        close()
        let host = NSHostingView(rootView: view.environment(\.layoutDirection, .rightToLeft))
        host.layoutSubtreeIfNeeded()
        let size = host.fittingSize
        let p = NSPanel(contentRect: NSRect(origin: .zero, size: size),
                        styleMask: [.nonactivatingPanel, .borderless], backing: .buffered, defer: false)
        p.isFloatingPanel = true
        p.level = .statusBar
        p.backgroundColor = .clear
        p.isOpaque = false
        p.hasShadow = true
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.contentView = host
        if let screen = NSScreen.main {
            let f = screen.visibleFrame
            p.setFrameOrigin(NSPoint(x: f.maxX - size.width - 16, y: f.maxY - size.height - 12))
        }
        p.alphaValue = 0
        p.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { $0.duration = 0.35; p.animator().alphaValue = 1 }
        panel = p
        if let t = autoClose {
            let w = DispatchWorkItem { [weak self] in self?.close() }
            closeWork = w
            DispatchQueue.main.asyncAfter(deadline: .now() + t, execute: w)
        }
    }

    func close() {
        closeWork?.cancel()
        guard let p = panel else { return }
        panel = nil
        NSAnimationContext.runAnimationGroup({ $0.duration = 0.3; p.animator().alphaValue = 0 }, completionHandler: { p.orderOut(nil) })
    }
}

struct PanelCard<Content: View>: View {
    var look: SkyLook
    var width: CGFloat = 380
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(20)
            .frame(width: width, alignment: .leading)
            .background(ZStack { SkyBackground(look: look); Veil(look: look) })
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(look.gold.opacity(0.55), lineWidth: 1))
            .foregroundStyle(look.text)
            .padding(8)
    }
}

/// Message for each kind of event.
struct EventCard: View {
    @ObservedObject var model: AppModel
    let event: AppEvent
    var meeting = false
    var close: () -> Void
    var openAdhkar: (AdhkarKind) -> Void

    var body: some View {
        let look = model.sky
        PanelCard(look: look) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    Image(systemName: icon).font(.system(size: 26)).foregroundStyle(look.gold).frame(width: 34)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(title).font(AppFont.naskh(25, bold: true)).fixedSize(horizontal: false, vertical: true)
                        if let s = subtitle { Text(s).font(.system(size: 14)).foregroundStyle(look.secondary) }
                    }
                    Spacer()
                    Button(action: close) { Image(systemName: "xmark").font(.system(size: 11, weight: .bold)) }
                        .buttonStyle(.plain).foregroundStyle(look.secondary)
                }
                actions(look)
            }
        }
    }

    private var p: Prayer { event.prayer ?? .dhuhr }
    private var isMeetingSilent: Bool { meeting }

    private var icon: String {
        switch event.kind {
        case .adhan: return model.playing != nil ? "speaker.wave.2.fill" : p.symbol
        case .pre: return "clock"
        case .after: return "hands.sparkles.fill"
        case .morningAdhkar: return "sunrise.fill"
        case .eveningAdhkar: return "sunset.fill"
        case .kahf: return "book.closed.fill"
        case .khutbah: return "building.columns.fill"
        case .suhoor: return "moon.haze.fill"
        }
    }

    private var title: String {
        switch event.kind {
        case .adhan:
            if p == .sunrise { return "وقت الشروق" }
            if p == .maghrib && model.ramadan { return "حان موعد الإفطار" }
            return "حان الآن موعد صلاة \(p.arabic)"
        case .pre: return "صلاة \(p.arabic) \(Fmt.countdownLong(Double(model.settings.preReminder) * 60, latin: model.latin))"
        case .after: return "تقبّل الله منك"
        case .morningAdhkar: return "أذكار الصباح"
        case .eveningAdhkar: return "أذكار المساء"
        case .kahf: return "يوم الجمعة: سورة الكهف"
        case .khutbah: return "خطبة الجمعة \(Fmt.countdownLong(Double(model.settings.khutbahBefore) * 60, latin: model.latin))"
        case .suhoor: return "وقت السحور"
        }
    }

    private var subtitle: String? {
        switch event.kind {
        case .adhan:
            if isMeetingSilent { return "أنت باجتماع، فطلع التنبيه بدون صوت" }
            return Fmt.time(event.time, latin: model.latin, use24h: model.settings.use24h)
        case .after: return "صلاة \(p.arabic)"
        case .suhoor:
            let fj = event.time.addingTimeInterval(Double(model.settings.suhoorBefore) * 60)
            return "الإمساك \(Fmt.time(fj.addingTimeInterval(-600), latin: model.latin, use24h: model.settings.use24h)) · الفجر \(Fmt.time(fj, latin: model.latin, use24h: model.settings.use24h))"
        case .kahf: return "وأكثر من الصلاة على النبي ﷺ"
        default: return nil
        }
    }

    @ViewBuilder private func actions(_ look: SkyLook) -> some View {
        switch event.kind {
        case .adhan:
            if model.playing != nil {
                Button { model.stopAdhan() } label: { Label("إيقاف الأذان", systemImage: "stop.fill") }
                    .buttonStyle(.borderedProminent).tint(look.gold)
            }
        case .after:
            VStack(alignment: .leading, spacing: 8) {
                if model.settings.adhkarAfterPrayer {
                    Button { openAdhkar(.after); close() } label: { Label("أذكار بعد الصلاة", systemImage: "hands.sparkles") }
                }
                if model.settings.khatmaOn && model.settings.khatmaAfterPrayer, let r = model.settings.khatma.nextPortion(model.now) {
                    Divider().opacity(0.4)
                    Text("وردك: صفحة \(Fmt.num(r.lowerBound, latin: model.latin))–\(Fmt.num(r.upperBound, latin: model.latin)) · سورة \(Quran.surah(onPage: r.lowerBound))")
                        .font(AppFont.naskh(18))
                    HStack {
                        Button { NSWorkspace.shared.open(Quran.url(page: r.lowerBound)) } label: { Label("افتح المصحف", systemImage: "book") }
                        Button { model.markRead(to: r.upperBound); close() } label: { Label("قرأت", systemImage: "checkmark") }
                            .buttonStyle(.borderedProminent).tint(look.gold)
                    }
                }
            }
            .controlSize(.regular)
        case .morningAdhkar:
            Button { openAdhkar(.morning); close() } label: { Label("ابدأ", systemImage: "play.fill") }.controlSize(.regular)
        case .eveningAdhkar:
            Button { openAdhkar(.evening); close() } label: { Label("ابدأ", systemImage: "play.fill") }.controlSize(.regular)
        case .kahf:
            Button { NSWorkspace.shared.open(URL(string: "https://quran.com/18")!); close() } label: { Label("اقرأ سورة الكهف", systemImage: "book") }.controlSize(.regular)
        default:
            EmptyView()
        }
    }
}
