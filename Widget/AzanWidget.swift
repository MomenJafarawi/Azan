import WidgetKit
import SwiftUI

struct AzanEntry: TimelineEntry {
    let date: Date
    let snap: WidgetSnapshot?
}

struct Provider: TimelineProvider {
    init() { AppFont.register(bundle: .main) }

    func placeholder(in context: Context) -> AzanEntry { AzanEntry(date: Date(), snap: WidgetSnapshot.load() ?? Self.sample) }
    func getSnapshot(in context: Context, completion: @escaping (AzanEntry) -> Void) {
        completion(AzanEntry(date: Date(), snap: WidgetSnapshot.load() ?? Self.sample))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<AzanEntry>) -> Void) {
        let snap = WidgetSnapshot.load()
        let now = Date()
        var dates: [Date] = [now]
        // every 10 minutes for the sky colours, plus every prayer moment
        for i in 1...36 { dates.append(now.addingTimeInterval(Double(i) * 600)) }
        if let s = snap {
            let sched = PrayerSchedule(input: s.input, tz: .current)
            for off in [0.0, 86400] {
                for (_, t) in sched.day(now.addingTimeInterval(off)).times where t > now && t < now.addingTimeInterval(6 * 3600) {
                    dates.append(t.addingTimeInterval(1))
                }
            }
        }
        let entries = dates.sorted().map { AzanEntry(date: $0, snap: snap) }
        completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(6 * 3600))))
    }

    static let sample = WidgetSnapshot(
        input: CalcInput(latitude: 52.3759, longitude: 9.732, method: .mwl, school: .shafi, highLat: .auto, offsets: [0, 0, 0, 0, 0, 0]),
        placeName: "هانوفر", hijriOffset: 0, latinDigits: false, use24h: true, khatmaOn: true, khatmaRead: 120, khatmaTarget: 140, updated: Date())
}


struct AzanWidgetView: View {
    var entry: AzanEntry
    @Environment(\.widgetFamily) var family

    var body: some View {
        if let s = entry.snap {
            content(s)
                .environment(\.layoutDirection, .rightToLeft)
                .environment(\.locale, Fmt.locale(latin: s.latinDigits))
                .containerBackground(for: .widget) {
                    SkyBackground(look: SkyLook.now(lat: s.input.latitude, lon: s.input.longitude, date: entry.date))
                }
        } else {
            VStack(spacing: 6) {
                Image(systemName: "moon.stars.fill").font(.title2)
                Text("افتح برنامج أذان مرة وحدة").font(.caption).multilineTextAlignment(.center)
            }
            .environment(\.layoutDirection, .rightToLeft)
            .containerBackground(for: .widget) { SkyBackground(look: SkyLook.at(altitude: -30, rising: false)) }
            .foregroundStyle(.white)
        }
    }

    static func withRamadan(_ i: CalcInput, _ r: Bool) -> CalcInput { var x = i; x.ramadan = r; return x }

    @ViewBuilder func content(_ s: WidgetSnapshot) -> some View {
        let look = SkyLook.now(lat: s.input.latitude, lon: s.input.longitude, date: entry.date)
        let ramadan = Fmt.isRamadan(entry.date, offset: s.hijriOffset)
        let sched = PrayerSchedule(input: Self.withRamadan(s.input, ramadan), tz: .current)
        let (p, t) = sched.next(after: entry.date)
        let (_, prev) = sched.previous(before: entry.date)
        switch family {
        case .systemMedium, .systemLarge:
            HStack(spacing: 12) {
                nextBlock(s, look, p, t, prev, ramadan: ramadan)
                    .frame(maxWidth: .infinity)
                Rectangle().fill(look.text.opacity(0.15)).frame(width: 0.7)
                list(s, look, sched, next: p, nextTime: t)
                    .frame(maxWidth: .infinity)
            }
            .foregroundStyle(look.text)
        default:
            nextBlock(s, look, p, t, prev, ramadan: ramadan)
                .foregroundStyle(look.text)
        }
    }

    func nextBlock(_ s: WidgetSnapshot, _ look: SkyLook, _ p: Prayer, _ t: Date, _ prev: Date, ramadan: Bool) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Image(systemName: ramadan ? "moon.stars.fill" : p.symbol).font(.system(size: 11))
                Text(Fmt.hijri(entry.date, offset: s.hijriOffset, latin: s.latinDigits, withYear: false)).font(AppFont.naskh(12))
            }
            .foregroundStyle(look.secondary)
            Spacer(minLength: 0)
            Text(p == .maghrib && ramadan ? "الإفطار" : p.arabic).font(AppFont.naskh(28, bold: true)).minimumScaleFactor(0.7)
            Text(t, style: .timer)
                .font(.system(size: 17, weight: .semibold).monospacedDigit())
                .foregroundStyle(look.gold)
            ProgressView(timerInterval: prev...max(t, prev.addingTimeInterval(1)), countsDown: false) { EmptyView() } currentValueLabel: { EmptyView() }
                .progressViewStyle(.linear)
                .tint(look.gold)
            Text("\(Fmt.time(t, latin: s.latinDigits, use24h: s.use24h)) · \(s.placeName)")
                .font(.system(size: 10)).foregroundStyle(look.secondary).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    func list(_ s: WidgetSnapshot, _ look: SkyLook, _ sched: PrayerSchedule, next: Prayer, nextTime: Date) -> some View {
        let day = sched.day(entry.date)
        let nextToday = Calendar.current.isDate(nextTime, inSameDayAs: entry.date)
        return VStack(alignment: .leading, spacing: 2) {
            ForEach(Prayer.allCases, id: \.self) { q in
                let hl = q == next && nextToday
                HStack {
                    Text(q.arabic).font(AppFont.naskh(13, bold: hl))
                    Spacer()
                    if let tt = day.times[q] {
                        Text(Fmt.time(tt, latin: s.latinDigits, use24h: s.use24h)).font(.system(size: 11, weight: hl ? .bold : .regular).monospacedDigit())
                    }
                }
                .padding(.horizontal, 5).padding(.vertical, 1)
                .background(RoundedRectangle(cornerRadius: 5).fill(hl ? look.gold.opacity(0.22) : .clear))
                .opacity(!hl && (day.times[q].map { $0 < entry.date } ?? false) ? 0.6 : 1)
            }
            if s.khatmaOn {
                HStack(spacing: 4) {
                    Image(systemName: "book.closed.fill").font(.system(size: 9))
                    ProgressView(value: Double(s.khatmaRead), total: Double(Quran.pages)).tint(look.gold)
                    Text(Fmt.num(s.khatmaRead, latin: s.latinDigits)).font(.system(size: 9).monospacedDigit())
                }
                .foregroundStyle(look.secondary)
                .padding(.top, 2)
            }
        }
    }
}

struct AzanWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "AzanWidget", provider: Provider()) { AzanWidgetView(entry: $0) }
            .configurationDisplayName("مواقيت الصلاة")
            .description("الصلاة الجاية والعد التنازلي بسماء حيّة.")
            .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main
struct AzanWidgets: WidgetBundle {
    var body: some Widget { AzanWidget() }
}
