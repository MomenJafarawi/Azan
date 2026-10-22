import SwiftUI

// MARK: - shared look

enum UI {
    static let pad: CGFloat = 22          // safe margin from every edge
    static let cardPad: CGFloat = 16
    static let radius: CGFloat = 18
}

struct Glass: ViewModifier {
    var look: SkyLook
    var radius: CGFloat = UI.radius
    var strong = false
    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(look.isDark ? Color.white.opacity(strong ? 0.14 : 0.09) : Color.white.opacity(strong ? 0.55 : 0.40))
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(LinearGradient(colors: [Color.white.opacity(look.isDark ? 0.28 : 0.75), Color.white.opacity(look.isDark ? 0.05 : 0.2)],
                                                 startPoint: .top, endPoint: .bottom), lineWidth: 1)
            )
            .shadow(color: .black.opacity(look.isDark ? 0.25 : 0.08), radius: 10, y: 4)
    }
}
extension View {
    func glass(_ look: SkyLook, radius: CGFloat = UI.radius, strong: Bool = false) -> some View { modifier(Glass(look: look, radius: radius, strong: strong)) }
}

struct GlassCard<Content: View>: View {
    var look: SkyLook
    @ViewBuilder var content: Content
    var body: some View {
        content.padding(UI.cardPad).frame(maxWidth: .infinity, alignment: .leading).glass(look)
    }
}

struct GoldBar: View {
    var value: Double
    var look: SkyLook
    var height: CGFloat = 6
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(look.text.opacity(0.14))
                Capsule()
                    .fill(LinearGradient(colors: [look.gold.opacity(0.7), look.gold], startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(height, g.size.width * value))
                    .shadow(color: look.gold.opacity(0.6), radius: 4)
            }
        }
        .frame(height: height)
    }
}

struct GoldRing: View {
    var value: Double
    var look: SkyLook
    var size: CGFloat = 54
    var label: String
    var body: some View {
        ZStack {
            Circle().stroke(look.text.opacity(0.14), lineWidth: 5)
            Circle().trim(from: 0, to: max(0.02, value))
                .stroke(LinearGradient(colors: [look.gold.opacity(0.7), look.gold], startPoint: .top, endPoint: .bottom),
                        style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .shadow(color: look.gold.opacity(0.5), radius: 3)
            Text(label).font(.system(size: 13, weight: .bold, design: .rounded))
        }
        .frame(width: size, height: size)
    }
}

/// readability veil over the live sky (darker/lighter towards the bottom)
struct Veil: View {
    var look: SkyLook
    var body: some View {
        LinearGradient(colors: [.clear, (look.isDark ? Color.black : Color.white).opacity(look.isDark ? 0.18 : 0.25)],
                       startPoint: .top, endPoint: .bottom)
    }
}

/// Gold tab buttons that stay readable on the navy background.
struct GoldTabs<T: Hashable>: View {
    var look: SkyLook
    var items: [(T, String, String)]     // value, title, SF symbol
    @Binding var selection: T
    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, it in
                let on = it.0 == selection
                Button { withAnimation(.easeOut(duration: 0.15)) { selection = it.0 } } label: {
                    HStack(spacing: 5) {
                        Image(systemName: it.2).font(.system(size: 12, weight: .semibold))
                        Text(it.1).font(.system(size: 13, weight: on ? .bold : .medium))
                    }
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(Capsule().fill(on ? look.gold : look.text.opacity(0.08)))
                    .overlay(Capsule().strokeBorder(on ? .clear : look.gold.opacity(0.35), lineWidth: 0.8))
                    .foregroundStyle(on ? Color(red: 0.06, green: 0.08, blue: 0.2) : look.text)
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - main panel

struct MainView: View {
    @ObservedObject var model: AppModel
    var visible: Bool = true
    var maxHeight: CGFloat = 900
    /// nil = natural height (used to measure); otherwise scroll inside this height
    var scrollHeight: CGFloat? = nil
    var openSettings: () -> Void
    var openAdhkar: (AdhkarKind) -> Void
    var quit: () -> Void
    var close: () -> Void = {}

    static let width: CGFloat = 400

    var body: some View {
        let look = model.sky
        Group {
            if let h = scrollHeight {
                ScrollView(showsIndicators: false) { content(look) }.frame(height: h)
            } else {
                content(look)
            }
        }
        .frame(width: Self.width)
        .background {
            ZStack {
                if let lat = model.settings.latitude, let lon = model.settings.longitude {
                    LiveSky(lat: lat, lon: lon, paused: !visible, orbBand: 300)
                } else {
                    SkyBackground(look: look)
                }
                Veil(look: look)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(look.gold.opacity(0.55), lineWidth: 1))
        .foregroundStyle(look.text)
        .environment(\.layoutDirection, .rightToLeft)
        .environment(\.locale, Fmt.locale(latin: model.latin))
        .focusEffectDisabled()
    }

    @ViewBuilder private func content(_ look: SkyLook) -> some View {
        if model.input == nil {
            noLocation(look).padding(UI.pad)
        } else {
            VStack(spacing: 14) {
                if let p = model.playing { stopBanner(p, look) }
                header(look)
                prayers(look)
                if model.ramadan { ramadanCard(look) }
                if model.settings.khatmaOn { khatmaCard(look) }
                adhkarRow(look)
                footer(look)
            }
            .padding(UI.pad)
        }
    }

    // MARK: header

    private func header(_ look: SkyLook) -> some View {
        VStack(spacing: 8) {
            HStack {
                Label(model.settings.placeName.isEmpty ? "موقعك" : model.settings.placeName, systemImage: "location.fill")
                    .font(.system(size: 13, weight: .medium))
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .glass(look, radius: 12)
                Spacer()
                Text(Fmt.hijri(model.now, offset: model.settings.hijriOffset, latin: model.latin))
                    .font(AppFont.naskh(16, bold: true))
                Button(action: close) {
                    Image(systemName: "xmark").font(.system(size: 11, weight: .bold))
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(look.text.opacity(0.12)))
                        .overlay(Circle().strokeBorder(look.gold.opacity(0.4), lineWidth: 0.8))
                }
                .buttonStyle(.plain)
                .help("إغلاق")
                .padding(.leading, 6)
            }
            .foregroundStyle(look.secondary)

            if let (p, t) = model.next {
                Text(p == .sunrise ? "الشروق" : (p == .maghrib && model.ramadan ? "الإفطار" : "صلاة \(p.arabic)"))
                    .font(AppFont.naskh(44, bold: true))
                    .foregroundStyle(look.gold)
                    .shadow(color: look.gold.opacity(0.35), radius: 10)
                    .padding(.top, 4)
                Text(Fmt.countdownLong(t.timeIntervalSince(model.now), latin: model.latin))
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundStyle(look.text)
                    .shadow(color: .black.opacity(look.isDark ? 0.3 : 0), radius: 4)
                GoldBar(value: model.progress, look: look)
                    .padding(.horizontal, 40).padding(.top, 6)
                Text("الأذان الساعة \(Fmt.time(t, latin: model.latin, use24h: model.settings.use24h))")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(look.secondary)
            }
        }
        .padding(.bottom, 4)
    }

    /// big stop button while the adhan is playing
    private func stopBanner(_ p: Prayer, _ look: SkyLook) -> some View {
        Button { model.stopAdhan() } label: {
            HStack(spacing: 12) {
                Image(systemName: "speaker.wave.2.fill").font(.system(size: 20))
                VStack(alignment: .leading, spacing: 2) {
                    Text("أذان \(p.arabic) شغّال").font(AppFont.naskh(18, bold: true))
                    Text("اكبس هون لإيقافه").font(.system(size: 12))
                }
                Spacer()
                Image(systemName: "stop.circle.fill").font(.system(size: 30))
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(look.gold))
            .foregroundStyle(Color(red: 0.08, green: 0.09, blue: 0.2))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: prayers

    private func prayers(_ look: SkyLook) -> some View {
        let day = model.today
        let nextP = model.next?.0
        let nextIsToday = model.next.map { Calendar.current.isDate($0.1, inSameDayAs: model.now) } ?? false
        return VStack(spacing: 4) {
            ForEach(Prayer.allCases, id: \.self) { p in
                let isNext = p == nextP && nextIsToday
                let passed = (day?.times[p].map { $0 <= model.now } ?? false)
                HStack(spacing: 12) {
                    Image(systemName: p.symbol).font(.system(size: 16)).frame(width: 24)
                        .foregroundStyle(isNext ? look.gold : look.secondary)
                    Text(p.arabic).font(AppFont.naskh(20, bold: isNext))
                    if isNext {
                        Text("التالية").font(.system(size: 11, weight: .bold))
                            .padding(.horizontal, 7).padding(.vertical, 2)
                            .background(Capsule().fill(look.gold.opacity(0.9))).foregroundStyle(Color.black.opacity(0.75))
                    }
                    Spacer()
                    if let t = day?.times[p] {
                        Text(Fmt.time(t, latin: model.latin, use24h: model.settings.use24h))
                            .font(.system(size: 17, weight: isNext ? .bold : .medium, design: .rounded).monospacedDigit())
                    }
                    modeButton(p, look)
                }
                .padding(.vertical, 7).padding(.horizontal, 12)
                .opacity(passed && !isNext ? 0.55 : 1)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(isNext ? look.gold.opacity(0.20) : .clear)
                )
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(isNext ? look.gold.opacity(0.7) : .clear, lineWidth: 1.2))
            }
        }
        .padding(8)
        .glass(look)
    }

    private func modeButton(_ p: Prayer, _ look: SkyLook) -> some View {
        let m = model.settings.mode(p)
        return Button {
            let order: [AlertMode] = [.adhan, .silent, .off]
            model.settings.setMode(order[((order.firstIndex(of: m) ?? 0) + 1) % 3], for: p)
        } label: {
            Image(systemName: m.symbol).font(.system(size: 13, weight: .semibold))
                .frame(width: 30, height: 30)
                .background(Circle().fill(look.text.opacity(m == .off ? 0.04 : 0.10)))
                .foregroundStyle(m == .off ? look.secondary.opacity(0.6) : look.text)
        }
        .buttonStyle(.plain)
        .help(m.arabic)
    }

    // MARK: ramadan

    private func ramadanCard(_ look: SkyLook) -> some View {
        let day = model.today
        let tomorrow = model.schedule?.day(model.now.addingTimeInterval(86400))
        let iftar = day?.times[.maghrib]
        var imsak = day?.times[.fajr].map { $0.addingTimeInterval(-600) }
        if let i = imsak, i < model.now { imsak = tomorrow?.times[.fajr].map { $0.addingTimeInterval(-600) } }
        return GlassCard(look: look) {
            VStack(alignment: .leading, spacing: 10) {
                Label("رمضان كريم", systemImage: "moon.stars.fill").font(AppFont.naskh(20, bold: true)).foregroundStyle(look.gold)
                HStack(spacing: 20) {
                    if let f = iftar, f > model.now {
                        stat("الإفطار بعد", Fmt.countdown(f.timeIntervalSince(model.now), latin: model.latin), look)
                    }
                    if let i = imsak {
                        stat("الإمساك", Fmt.time(i, latin: model.latin, use24h: model.settings.use24h), look)
                    }
                    Spacer()
                }
            }
        }
    }

    private func stat(_ title: String, _ value: String, _ look: SkyLook) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(size: 12)).foregroundStyle(look.secondary)
            Text(value).font(.system(size: 20, weight: .bold, design: .rounded))
        }
    }

    // MARK: khatma

    private func khatmaCard(_ look: SkyLook) -> some View {
        let k = model.settings.khatma
        let pct = Int((Double(k.lastRead) / Double(Quran.pages) * 100).rounded())
        return GlassCard(look: look) {
            HStack(alignment: .center, spacing: 14) {
                GoldRing(value: Double(k.lastRead) / Double(Quran.pages), look: look, label: "\(Fmt.num(pct, latin: model.latin))٪")
                VStack(alignment: .leading, spacing: 6) {
                    Text("وردي من القرآن").font(AppFont.naskh(20, bold: true))
                    if k.finished {
                        Text("ختمت القرآن، تقبّل الله منك").font(.system(size: 13))
                        Button("ابدأ ختمة جديدة") { model.newKhatma(days: model.settings.khatmaDays) }
                    } else if let r = k.nextPortion(model.now) {
                        Text("صفحة \(Fmt.num(r.lowerBound, latin: model.latin))–\(Fmt.num(r.upperBound, latin: model.latin)) · سورة \(Quran.surah(onPage: r.lowerBound))")
                            .font(.system(size: 13, weight: .medium))
                        let behind = k.behind(model.now)
                        Text(behind == 0 ? "أنت على الموعد، ما شاء الله" : "باقي عليك اليوم \(Fmt.num(behind, latin: model.latin)) صفحة")
                            .font(.system(size: 12)).foregroundStyle(behind == 0 ? look.gold : look.secondary)
                        HStack(spacing: 8) {
                            pill("افتح المصحف", "book", look, filled: false) { NSWorkspace.shared.open(Quran.url(page: r.lowerBound)) }
                            pill("قرأت", "checkmark", look, filled: true) { model.markRead(to: r.upperBound) }
                        }
                        .padding(.top, 2)
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func pill(_ title: String, _ icon: String, _ look: SkyLook, filled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon).font(.system(size: 13, weight: .semibold))
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(Capsule().fill(filled ? look.gold : look.text.opacity(0.10)))
                .foregroundStyle(filled ? Color.black.opacity(0.78) : look.text)
        }
        .buttonStyle(.plain)
    }

    // MARK: adhkar

    private func adhkarRow(_ look: SkyLook) -> some View {
        HStack(spacing: 10) {
            ForEach(AdhkarKind.allCases, id: \.self) { k in
                Button { openAdhkar(k) } label: {
                    VStack(spacing: 5) {
                        Image(systemName: k.symbol).font(.system(size: 18)).foregroundStyle(look.gold)
                        Text(k.short).font(AppFont.naskh(16, bold: true))
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 12)
                    .glass(look, radius: 16)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func footer(_ look: SkyLook) -> some View {
        HStack {
            Button(action: openSettings) {
                Label("الإعدادات", systemImage: "gearshape").font(.system(size: 13, weight: .medium))
            }
            Spacer()
            Text(Fmt.gregorian(model.now, latin: model.latin)).font(.system(size: 13))
            Spacer()
            Button(action: quit) { Image(systemName: "power").font(.system(size: 14)) }.help("إنهاء")
        }
        .buttonStyle(.plain)
        .foregroundStyle(look.secondary)
        .padding(.horizontal, 4).padding(.top, 2)
    }

    private func noLocation(_ look: SkyLook) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "location.slash").font(.system(size: 36))
            Text("محتاج أعرف مدينتك").font(AppFont.naskh(26, bold: true))
            Text(model.locationDenied ? "خدمة الموقع مقفلة لهالبرنامج. اختار مدينتك من الإعدادات، أو افتح خدمة الموقع."
                 : "عم نحدد موقعك…").multilineTextAlignment(.center).font(.system(size: 14))
            pill("اختيار المدينة", "mappin", look, filled: true, action: openSettings)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
    }
}
