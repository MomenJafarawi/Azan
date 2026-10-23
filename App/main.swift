import AppKit
import SwiftUI
import Combine

final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel.shared
    var status: NSStatusItem!
    lazy var menuPanel = MenuPanelController(model: model)
    let floating = FloatingPanel()
    var adhkarWindow: NSWindow?
    var settingsWindow: NSWindow?
    var adhanCardOpen = false
    lazy var desk = DeskWidgetController(model: model)
    var deskSub: Any?

    func applicationDidFinishLaunching(_ n: Notification) {
        AppFont.register(bundle: .main)
        status = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        status.button?.target = self
        status.button?.action = #selector(togglePopover)
        status.button?.imagePosition = .imageLeading

        menuPanel.openSettings = { [weak self] in self?.showSettings() }
        menuPanel.openAdhkar = { [weak self] k in self?.showAdhkar(k) }

        model.onTick = { [weak self] in self?.updateTitle() }
        model.onEvent = { [weak self] e, meeting in self?.showEvent(e, meeting: meeting) }
        model.onAdhanEnded = { [weak self] in
            guard let self else { return }
            self.updateTitle()
            if self.adhanCardOpen {
                self.adhanCardOpen = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 30) { [weak self] in self?.floating.close() }
            }
        }
        SelfCheck.offerMoveToApplications()
        Updater.shared.onAvailable = { [weak self] _ in self?.showUpdateCard() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) { [weak self] in
            if self?.model.settings.autoUpdateCheck == true { Updater.shared.check() }
        }
        Timer.scheduledTimer(withTimeInterval: 6 * 3600, repeats: true) { [weak self] _ in
            if self?.model.settings.autoUpdateCheck == true { Updater.shared.check() }
        }
        model.check = SelfCheck.run(model: model)
        model.start()
        desk.onOpenSettings = { [weak self] in self?.showSettings() }
        desk.onClick = { [weak self] in
            guard let self else { return }
            if self.model.playing != nil { self.model.stopAdhan() } else { self.togglePopover() }
        }
        model.onTestAdhan = { [weak self] in self?.testAdhan() }
        desk.apply()
        deskSub = model.$settings.removeDuplicates { $0.deskOn == $1.deskOn && $0.deskSize == $1.deskSize && $0.deskOnTop == $1.deskOnTop && $0.deskScale == $1.deskScale }
            .dropFirst().receive(on: DispatchQueue.main).sink { [weak self] _ in self?.desk.apply() }
        updateTitle()
        Log.write("started")

        // test switches (only with a separate data folder)
        let env = ProcessInfo.processInfo.environment
        if env["AZAN_DATA"] != nil, let show = env["AZAN_SHOW"] {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self.testShow(show) }
        }
    }

    func updateTitle() {
        guard let b = status.button else { return }
        let img = NSImage(systemSymbolName: model.playing != nil ? "speaker.wave.2.fill" : "moon.stars.fill", accessibilityDescription: "أذان")
        img?.isTemplate = true
        b.image = img
        if let (p, t) = model.next {
            b.title = " \(p.arabic) \(Fmt.countdown(t.timeIntervalSince(Date()), latin: model.latin))"
        } else {
            b.title = ""
        }
    }

    @objc func togglePopover() {
        guard let b = status.button else { return }
        menuPanel.toggle(from: b)
    }

    func showEvent(_ e: AppEvent, meeting: Bool) {
        let view = EventCard(model: model, event: e, meeting: meeting, close: { [weak self] in self?.floating.close() },
                             openAdhkar: { [weak self] k in self?.showAdhkar(k) })
        let auto: TimeInterval? = switch e.kind {
        case .adhan: model.playing != nil ? nil : 120
        case .pre, .khutbah: 45
        case .after: 20 * 60
        default: 10 * 60
        }
        floating.show(view, autoClose: auto)
        adhanCardOpen = e.kind == .adhan && model.playing != nil
    }

    func showUpdateCard() {
        floating.show(UpdateCard(model: model, close: { [weak self] in self?.floating.close() }), autoClose: nil)
    }

    func showAdhkar(_ k: AdhkarKind) {
        menuPanel.close()
        let w = adhkarWindow ?? makeWindow(title: "الأذكار", size: NSSize(width: 520, height: 680))
        w.contentViewController = NSHostingController(rootView: AdhkarView(model: model, kind: k))
        adhkarWindow = w
        w.center(); w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func showSettings() {
        menuPanel.close()
        let w = settingsWindow ?? makeWindow(title: "إعدادات أذان", size: NSSize(width: 600, height: 640))
        if settingsWindow == nil { w.contentViewController = NSHostingController(rootView: SettingsView(model: model)) }
        settingsWindow = w
        w.center(); w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func makeWindow(title: String, size: NSSize) -> NSWindow {
        let w = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled, .closable, .fullSizeContentView],
                         backing: .buffered, defer: false)
        w.title = title
        w.titlebarAppearsTransparent = true
        w.titleVisibility = .hidden
        w.isReleasedWhenClosed = false
        w.isMovableByWindowBackground = true
        return w
    }

    /// full adhan rehearsal for the next prayer: card + sound + smart pause
    func testAdhan() {
        let p = model.nextPrayer?.0 ?? .maghrib
        model.startAdhan(p)
        showEvent(AppEvent(kind: .adhan, prayer: p, time: Date(), window: 60), meeting: false)
    }

    private func testShow(_ what: String) {
        switch what {
        case "popover": togglePopover()
        case "settings": showSettings()
        case "adhkar": showAdhkar(.morning)
        case "desk": desk.apply()
        case "testadhan": testAdhan()
        case "announce": model.announce(.fajr)
        case "update": Updater.shared.check(force: true)
        case "updateinstall":
            Updater.shared.onAvailable = { [weak self] _ in self?.showUpdateCard(); Updater.shared.install() }
            Updater.shared.check(force: true)
        case "mediatest":
            DispatchQueue.global().async {
                let procs = AudioSignal.outputPIDs(excludingBundles: [])
                for (obj, pid) in procs {
                    let name = NSRunningApplication(processIdentifier: pid)?.localizedName ?? "pid \(pid)"
                    if #available(macOS 14.2, *) { Log.write("mediatest: \(name) output open, peak \(AudioSignal.peak(of: obj, seconds: 0.6))") }
                }
                if procs.isEmpty { Log.write("mediatest: no app has audio output open") }
            }
        case "playing": testAdhan(); DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { self.togglePopover() }
        default:
            if what.hasPrefix("event:"), let k = EventKind(rawValue: String(what.dropFirst(6))) {
                let p = Prayer(rawValue: Int(ProcessInfo.processInfo.environment["AZAN_PRAYER"] ?? "3") ?? 3)
                showEvent(AppEvent(kind: k, prayer: p, time: k == .missed ? Date().addingTimeInterval(-1500) : Date(), window: 60, until: k == .missed ? Date().addingTimeInterval(3600) : nil), meeting: ProcessInfo.processInfo.environment["AZAN_MEETING"] != nil)
            }
        }
    }
}

// MARK: - self test (runs in build.sh before install)

func selfTest(resources: String, bundle: String?) -> Int32 {
    Log.muted = true
    var fails = 0
    func check(_ ok: Bool, _ what: String) { if !ok { fails += 1; print("FAIL:", what) } else { print("ok:", what) } }

    // 1. prayer times against AlAdhan reference values (±1 minute)
    func hm(_ d: Date?, _ tz: TimeZone) -> Int {
        guard let d = d else { return -999 }
        var c = Calendar(identifier: .gregorian); c.timeZone = tz
        let x = c.dateComponents([.hour, .minute], from: d); return x.hour! * 60 + x.minute!
    }
    let cases: [(String, Double, Double, CalcMethod, String, String, [String])] = [
        ("Hannover winter", 52.3759, 9.732, .mwl, "Europe/Berlin", "2026-10-21", ["06:03", "07:57", "13:06", "15:42", "18:14", "20:01"]),
        ("Hannover summer", 52.3759, 9.732, .mwl, "Europe/Berlin", "2026-06-21", ["03:57", "04:59", "13:23", "17:48", "21:47", "22:49"]),
        ("Makkah", 21.4225, 39.8262, .ummAlQura, "Asia/Riyadh", "2026-10-21", ["05:02", "06:19", "12:05", "15:25", "17:52", "19:22"]),
        ("Istanbul", 41.0082, 28.9784, .diyanet, "Europe/Istanbul", "2026-10-21", ["05:50", "07:15", "12:54", "15:53", "18:22", "19:41"]),
    ]
    for (name, lat, lon, m, tzName, day, ref) in cases {
        let tz = TimeZone(identifier: tzName)!
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH:mm"; f.timeZone = tz
        let r = PrayerCalc.compute(CalcInput(latitude: lat, longitude: lon, method: m, school: .shafi, highLat: .seventhOfNight, offsets: [0, 0, 0, 0, 0, 0]),
                                   day: f.date(from: day + " 12:00")!, tz: tz)
        var worst = 0
        for (i, p) in Prayer.allCases.enumerated() {
            let parts = ref[i].split(separator: ":").map { Int($0)! }
            worst = max(worst, abs(hm(r.times[p], tz) - (parts[0] * 60 + parts[1])))
        }
        check(worst <= 1, "times \(name) (max diff \(worst) min)")
    }
    // 2. country method mapping
    check(CalcMethod.forCountry("DE") == .mwl && CalcMethod.forCountry("TR") == .diyanet && CalcMethod.forCountry("SA") == .ummAlQura, "method by country")
    // 3. khatma math
    let start = Date().addingTimeInterval(-2 * 86400)
    let k = KhatmaPlan(days: 30, start: start, lastRead: 0)
    check(k.dayIndex(Date()) == 3 && k.target(Date()) == 61 && k.chunk == 5, "khatma plan (day 3, target 61, 5 pages/prayer)")
    check(KhatmaPlan(days: 30, start: start, lastRead: 604).nextPortion(Date()) == nil, "khatma finished")
    check(Quran.surah(onPage: 293) == "الكهف" && Quran.surah(onPage: 604) == "الناس" && Quran.juz(ofPage: 582) == 30 && Quran.juz(ofPage: 21) == 1, "surah/juz lookup")
    // 4. old or partial settings files still load
    let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
    let partial = #"{"latitude": 52.37, "longitude": 9.73, "voice": "aqsa", "unknownFutureField": 5}"#
    if let s = try? dec.decode(Settings.self, from: partial.data(using: .utf8)!) {
        check(s.voice == "aqsa" && s.latitude == 52.37 && s.khatmaDays == 30 && s.mode(.sunrise) == .off, "partial settings decode")
    } else { check(false, "partial settings decode") }
    let wrongType = #"{"latitude": "oops", "volume": "x", "khatmaRead": 50}"#
    if let s = try? dec.decode(Settings.self, from: wrongType.data(using: .utf8)!) {
        check(s.latitude == nil && s.volume == 0.8 && s.khatmaRead == 50, "bad field types fall back to defaults")
    } else { check(false, "bad field types fall back to defaults") }
    // 5. unreadable settings are kept and never overwritten
    let tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("azan-selftest-\(getpid())")
    try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    let st = SettingsStore(dir: tmp)
    try? "not json {".data(using: .utf8)!.write(to: st.file)
    _ = st.load()
    st.save(Settings())
    check((try? String(contentsOf: st.file, encoding: .utf8)) == "not json {", "unreadable settings not overwritten")
    try? FileManager.default.removeItem(at: tmp)
    // 6. resources
    let book = AdhkarBook.load(URL(fileURLWithPath: resources + "/adhkar.json"))
    check((book?.morning.count ?? 0) > 15 && (book?.evening.count ?? 0) > 15 && (book?.after.count ?? 0) > 5, "adhkar file loads")
    for v in Voice.all {
        check(FileManager.default.fileExists(atPath: resources + "/Sounds/\(v.id).mp3"), "sound \(v.id)")
    }
    // 7. Majed recordings and the file manifest of the built app
    for k in ["fajr", "sunrise", "dhuhr", "asr", "maghrib", "isha", "iftar"] {
        check(FileManager.default.fileExists(atPath: resources + "/Speech/\(k).m4a"), "speech \(k)")
    }
    if let b = bundle {
        let (n, bad) = SelfCheck.verify(base: URL(fileURLWithPath: b))
        check(n >= 18 && bad.isEmpty, "manifest: \(n) files verified, broken=\(bad)")
    }
    check(Updater.isNewer("1.2.10", than: "1.2.9") && Updater.isNewer("1.3", than: "1.2.9") && !Updater.isNewer("1.2.1", than: "1.2.1") && !Updater.isNewer("1.2", than: "1.2.0"), "version compare")
    // 8. missed adhan card after sleep (Hannover, MWL)
    do {
        let tz = TimeZone.current
        let sch = PrayerSchedule(input: CalcInput(latitude: 52.3759, longitude: 9.732, method: .mwl, school: .shafi, highLat: .seventhOfNight, offsets: [0, 0, 0, 0, 0, 0]), tz: tz)
        let d = sch.day(Date())
        if let asr = d.times[.asr], let mg = d.times[.maghrib], let fj = d.times[.fajr], let sr = d.times[.sunrise] {
            let e = AppEvent(kind: .adhan, prayer: .asr, time: asr, window: 120)
            let m = AppModel.missedEvent(e, now: asr.addingTimeInterval(1800), schedule: sch)
            check(m?.kind == .missed && m?.until == mg, "missed asr card shown while asr time runs")
            check(AppModel.missedEvent(e, now: mg.addingTimeInterval(60), schedule: sch) == nil, "no missed card after asr time ended")
            let f = AppEvent(kind: .adhan, prayer: .fajr, time: fj, window: 120)
            check(AppModel.missedEvent(f, now: fj.addingTimeInterval(600), schedule: sch)?.until == sr, "missed fajr ends at sunrise")
            check(AppModel.missedEvent(AppEvent(kind: .adhan, prayer: .sunrise, time: sr, window: 120), now: sr.addingTimeInterval(600), schedule: sch) == nil, "no missed card for sunrise")
        } else { check(false, "missed card times") }
    }
    // 9. hijri + sky
    check(Fmt.hijri(Date(), offset: 0, latin: false).hasSuffix("هـ"), "hijri text")
    check(SkyLook.at(altitude: -30, rising: false).isDark && !SkyLook.at(altitude: 50, rising: true).isDark, "sky text contrast")
    print(fails == 0 ? "SELFTEST PASSED" : "SELFTEST FAILED (\(fails))")
    return fails == 0 ? 0 : 1
}

let args = CommandLine.arguments
if args.count >= 3, args[1] == "--selftest" {
    exit(selfTest(resources: args[2], bundle: args.count >= 4 ? args[3] : nil))
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
