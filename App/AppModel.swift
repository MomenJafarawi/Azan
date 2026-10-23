import AppKit
import SwiftUI
import WidgetKit
import IOKit.pwr_mgt

enum EventKind: String {
    case adhan, pre, after, morningAdhkar, eveningAdhkar, kahf, khutbah, suhoor, missed
}

struct AppEvent {
    let kind: EventKind
    let prayer: Prayer?
    let time: Date
    /// how long after `time` it may still fire (sleep, late start)
    let window: TimeInterval
    /// for a missed adhan: when the prayer time ends
    var until: Date? = nil
    var key: String {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"
        return "\(f.string(from: time))|\(kind.rawValue)|\(prayer?.rawValue ?? -1)"
    }
}

final class AppModel: ObservableObject {
    static let shared = AppModel()

    @Published var settings: Settings { didSet { if settings != oldValue { settingsChanged(old: oldValue) } } }
    @Published var now = Date()
    @Published var playing: Prayer? = nil
    @Published var locationDenied = false
    @Published var check = CheckReport()

    let store: SettingsStore
    let location = LocationService()
    let player = AdhanPlayer()
    let announcer = Announcer()
    private var fired = Set<String>()
    private var pausedMedia = PausedMedia()
    private var timer: Timer?
    private var awakeID: IOPMAssertionID = 0
    private var lastTick: Date? = nil
    private var lastWidgetDay = ""
    var onEvent: ((AppEvent, Bool) -> Void)?
    var onTick: (() -> Void)?
    var onAdhanEnded: (() -> Void)?
    var onTestAdhan: (() -> Void)?

    init() {
        store = SettingsStore()
        settings = store.load()
        location.onUpdate = { [weak self] loc, name, cc in self?.gotLocation(loc, name: name, country: cc) }
        location.onDenied = { [weak self] in self?.locationDenied = true }
        player.onFinish = { [weak self] in self?.adhanEnded() }
    }

    // MARK: derived

    var ramadan: Bool { Fmt.isRamadan(now, offset: settings.hijriOffset) }
    var input: CalcInput? { settings.calcInput(ramadan: ramadan) }
    var schedule: PrayerSchedule? { input.map { PrayerSchedule(input: $0, tz: .current) } }
    var today: DayTimes? { schedule?.day(now) }
    var next: (Prayer, Date)? { schedule?.next(after: now) }
    var nextPrayer: (Prayer, Date)? { schedule?.next(after: now, includeSunrise: false) }
    var latin: Bool { settings.latinDigits }
    var sky: SkyLook {
        guard let lat = settings.latitude, let lon = settings.longitude else { return SkyLook.at(altitude: 30, rising: true) }
        return SkyLook.now(lat: lat, lon: lon, date: now)
    }

    /// share of time passed between the previous and the next event (0...1)
    var progress: Double {
        guard let s = schedule else { return 0 }
        let (_, prev) = s.previous(before: now)
        let (_, nxt) = s.next(after: now)
        let total = nxt.timeIntervalSince(prev)
        return total > 0 ? min(1, max(0, now.timeIntervalSince(prev) / total)) : 0
    }

    // MARK: lifecycle

    func start() {
        if settings.autoLocation || settings.latitude == nil { location.refresh() }
        LoginItem.set(settings.launchAtLogin)
        store.dailyBackup()
        writeWidget()
        // events that are already past at start are only marked, never replayed
        markPastAsFired()
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer!, forMode: .common)
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.tick()
            if self?.settings.autoLocation == true { self?.location.refresh() }
        }
        // refresh location every 3 hours (travel)
        Timer.scheduledTimer(withTimeInterval: 3 * 3600, repeats: true) { [weak self] _ in
            if self?.settings.autoLocation == true { self?.location.refresh() }
        }
    }

    private func gotLocation(_ loc: CLLocationLike, name: String, country: String?) {
        guard settings.autoLocation else { return }
        var s = settings
        // ignore tiny moves so times do not jitter
        if let la = s.latitude, let lo = s.longitude,
           abs(la - loc.coordinate.latitude) < 0.03, abs(lo - loc.coordinate.longitude) < 0.03, !s.placeName.isEmpty { return }
        s.latitude = (loc.coordinate.latitude * 10000).rounded() / 10000
        s.longitude = (loc.coordinate.longitude * 10000).rounded() / 10000
        if !name.isEmpty { s.placeName = name }
        s.countryCode = country
        settings = s
        locationDenied = false
        Log.write("location: \(name) \(country ?? "")")
    }

    private func settingsChanged(old: Settings) {
        store.save(settings)
        if old.launchAtLogin != settings.launchAtLogin { LoginItem.set(settings.launchAtLogin) }
        writeWidget()
        objectWillChange.send()
    }

    // MARK: events

    func events(around date: Date) -> [AppEvent] {
        guard let s = schedule else { return [] }
        var out: [AppEvent] = []
        let cal = Calendar.current
        for dayOffset in [-1, 0, 1] {
            let d = date.addingTimeInterval(Double(dayOffset) * 86400)
            let t = s.day(d)
            for p in Prayer.allCases {
                guard let pt = t.times[p] else { continue }
                let mode = settings.mode(p)
                if mode != .off { out.append(AppEvent(kind: .adhan, prayer: p, time: pt, window: 120)) }
                if p.isPrayer, mode != .off, settings.preReminder > 0 {
                    out.append(AppEvent(kind: .pre, prayer: p, time: pt.addingTimeInterval(-Double(settings.preReminder) * 60), window: 120))
                }
                if p.isPrayer, settings.adhkarAfterPrayer || (settings.khatmaOn && settings.khatmaAfterPrayer) {
                    out.append(AppEvent(kind: .after, prayer: p, time: pt.addingTimeInterval(20 * 60), window: 30 * 60))
                }
            }
            if settings.adhkarMorning, let sr = t.times[.sunrise], let dh = t.times[.dhuhr] {
                out.append(AppEvent(kind: .morningAdhkar, prayer: nil, time: sr.addingTimeInterval(15 * 60), window: dh.timeIntervalSince(sr) - 20 * 60))
            }
            if settings.adhkarEvening, let asr = t.times[.asr], let mg = t.times[.maghrib] {
                out.append(AppEvent(kind: .eveningAdhkar, prayer: nil, time: asr.addingTimeInterval(30 * 60), window: max(600, mg.timeIntervalSince(asr) - 30 * 60)))
            }
            if settings.jumuah, cal.component(.weekday, from: d) == 6 {
                if let k = cal.date(bySettingHour: 10, minute: 0, second: 0, of: d) {
                    out.append(AppEvent(kind: .kahf, prayer: nil, time: k, window: 5 * 3600))
                }
                if let dh = t.times[.dhuhr] {
                    out.append(AppEvent(kind: .khutbah, prayer: .dhuhr, time: dh.addingTimeInterval(-Double(settings.khutbahBefore) * 60), window: 600))
                }
            }
            if Fmt.isRamadan(d, offset: settings.hijriOffset), let fj = t.times[.fajr] {
                out.append(AppEvent(kind: .suhoor, prayer: .fajr, time: fj.addingTimeInterval(-Double(settings.suhoorBefore) * 60), window: 600))
            }
        }
        return out
    }

    private func markPastAsFired() {
        // reminders already shown before a restart stay shown
        for k in UserDefaults.standard.stringArray(forKey: "firedKeys") ?? [] { fired.insert(k) }
        let n = Date()
        for e in events(around: n) where e.time <= n {
            // keep long-window reminders (adhkar, kahf) alive, they are still useful late
            if [.morningAdhkar, .eveningAdhkar, .kahf].contains(e.kind) && n.timeIntervalSince(e.time) < e.window { continue }
            fired.insert(e.key)
        }
    }

    func tick() {
        now = Date()
        let n = now
        let list = events(around: n)
        let prev = lastTick; lastTick = n
        var missed: AppEvent? = nil
        for e in list where e.time <= n && !fired.contains(e.key) {
            fired.insert(e.key)
            if n.timeIntervalSince(e.time) > e.window {
                // the Mac slept through the adhan (no tick at adhan time): say so quietly if the prayer time is still running
                if e.kind == .adhan, let pt = prev, pt < e.time, let s = schedule, let m = AppModel.missedEvent(e, now: n, schedule: s) { missed = m }
                continue
            }
            fire(e)
        }
        if let m = missed { fire(m) }
        holdAwake(list, n)
        if fired.count > 400 { fired = Set(fired.suffix(200)) }
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"
        let day = f.string(from: n)
        if day != lastWidgetDay { lastWidgetDay = day; writeWidget(); store.dailyBackup() }
        onTick?()
    }

    /// card for an adhan that passed while the Mac was asleep, only while its prayer time is still running
    static func missedEvent(_ e: AppEvent, now: Date, schedule: PrayerSchedule) -> AppEvent? {
        guard e.kind == .adhan, let p = e.prayer, p.isPrayer else { return nil }
        let end = schedule.next(after: e.time.addingTimeInterval(1)).1
        guard now < end.addingTimeInterval(-60) else { return nil }
        return AppEvent(kind: .missed, prayer: p, time: e.time, window: 0, until: end)
    }

    /// keep the Mac from falling asleep on its own from 10 minutes before an adhan until it is over
    private func holdAwake(_ list: [AppEvent], _ n: Date) {
        let need = playing != nil || list.contains { $0.kind == .adhan && n >= $0.time.addingTimeInterval(-600) && n <= $0.time.addingTimeInterval(180) }
        if need && awakeID == 0 {
            var id: IOPMAssertionID = 0
            if IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleSystemSleep as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                           "Azan: prayer time is near" as CFString, &id) == kIOReturnSuccess {
                awakeID = id; Log.write("sleep held for adhan")
            }
        } else if !need && awakeID != 0 {
            IOPMAssertionRelease(awakeID); awakeID = 0; Log.write("sleep allowed again")
        }
    }

    private func fire(_ e: AppEvent) {
        let keep = (UserDefaults.standard.stringArray(forKey: "firedKeys") ?? []).suffix(60) + [e.key]
        UserDefaults.standard.set(Array(keep), forKey: "firedKeys")
        Log.write("event \(e.kind.rawValue) \(e.prayer?.arabic ?? "")")
        if e.kind == .adhan, let p = e.prayer {
            let meeting = settings.meetingSilent && AudioState.micInUse()
            if settings.mode(p) == .adhan && !meeting {
                startAdhan(p)
            } else if settings.mode(p) != .off && settings.speakOn && (!meeting || settings.speakInMeeting) {
                announce(p)
            }
            onEvent?(e, meeting && settings.mode(p) == .adhan)
            return
        }
        onEvent?(e, false)
    }

    /// silent alert with a spoken line repeated a few times
    func announce(_ p: Prayer) {
        let voice = settings.speakTakbir ? (p == .fajr ? settings.fajrVoice : settings.voice) : nil
        announcer.announce(Announcer.text(for: p, ramadan: ramadan), key: Announcer.key(for: p, ramadan: ramadan), voiceID: voice, times: settings.speakRepeats, volume: settings.speakVolume)
    }

    func startAdhan(_ p: Prayer) {
        playing = p
        let voice = p == .fajr ? settings.fajrVoice : settings.voice
        guard settings.smartPause else { player.play(voice, volume: settings.volume); return }
        // find out what is really playing (takes about half a second), pause only that, then start the adhan
        let allowKey = MediaKeys.trusted
        DispatchQueue.global(qos: .userInitiated).async {
            let m = MediaControl.pauseAll(allowKey: allowKey)
            DispatchQueue.main.async {
                self.pausedMedia = m
                if self.playing == p { self.player.play(voice, volume: self.settings.volume) }
                else if !m.isEmpty { self.pausedMedia = PausedMedia(); MediaControl.resume(m) }
            }
        }
    }

    func stopAdhan() { player.stop(); announcer.stop() }

    private func adhanEnded() {
        playing = nil
        if !pausedMedia.isEmpty {
            let m = pausedMedia
            pausedMedia = PausedMedia()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { MediaControl.resume(m) }
        }
        onAdhanEnded?()
    }

    func preview(_ voice: String) {
        if player.isPlaying { player.stop(notify: false); playing = nil; return }
        player.play(voice, volume: settings.volume, fadeIn: false)
    }

    // MARK: khatma

    func markRead(to page: Int) {
        var s = settings
        s.khatmaRead = min(Quran.pages, max(s.khatmaRead, page))
        if s.khatmaRead >= Quran.pages { s.khatmaCount += 1 }
        settings = s
    }

    func newKhatma(days: Int) {
        var s = settings
        s.khatmaDays = days; s.khatmaStart = Date(); s.khatmaRead = 0
        settings = s
    }

    // MARK: widget

    func writeWidget() {
        guard let inp = input else { return }
        let k = settings.khatma
        let snap = WidgetSnapshot(input: inp, placeName: settings.placeName, hijriOffset: settings.hijriOffset,
                                  latinDigits: settings.latinDigits, use24h: settings.use24h, khatmaOn: settings.khatmaOn,
                                  khatmaRead: k.lastRead, khatmaTarget: k.target(Date()), updated: Date())
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601
        if let d = try? enc.encode(snap) {
            try? d.write(to: Paths.widgetFile, options: .atomic)
            chmod(Paths.widgetFile.path, 0o644)
        }
        WidgetCenter.shared.reloadAllTimelines()
    }
}

import CoreLocation
typealias CLLocationLike = CLLocation
