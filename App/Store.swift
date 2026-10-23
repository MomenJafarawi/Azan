import Foundation

enum AlertMode: String, Codable, CaseIterable {
    case adhan, silent, off
    var arabic: String {
        switch self { case .adhan: return "أذان"; case .silent: return "تنبيه صامت"; case .off: return "بدون" }
    }
    var symbol: String {
        switch self { case .adhan: return "speaker.wave.2.fill"; case .silent: return "bell"; case .off: return "bell.slash" }
    }
}

struct Voice: Identifiable, Hashable {
    let id: String
    let name: String
    static let all: [Voice] = [
        Voice(id: "makkah", name: "مكة (علي ملا)"),
        Voice(id: "makkah_fajr", name: "فجر الحرم المكي"),
        Voice(id: "madinah", name: "الحرم المدني"),
        Voice(id: "madinah_fajr", name: "فجر الحرم المدني"),
        Voice(id: "alafasy", name: "مشاري العفاسي"),
        Voice(id: "alafasy_fajr", name: "فجر مشاري العفاسي"),
        Voice(id: "aqsa", name: "المسجد الأقصى"),
        Voice(id: "abdulbasit", name: "عبد الباسط عبد الصمد"),
    ]
    static func name(_ id: String) -> String { all.first { $0.id == id }?.name ?? id }
}

/// Every field is decoded with a default, so adding fields later can never make old files unreadable.
struct Settings: Codable, Equatable {
    var autoLocation = true
    var latitude: Double? = nil
    var longitude: Double? = nil
    var placeName = ""
    var countryCode: String? = nil
    var autoMethod = true
    var method: CalcMethod = .mwl
    var school: AsrSchool = .shafi
    var highLat: HighLatRule = .auto
    var offsets: [Double] = [0, 0, 0, 0, 0, 0]
    var hijriOffset = 0
    var latinDigits = false
    var use24h = true

    var modes: [String: AlertMode] = [:]       // key: Prayer rawValue
    var voice = "makkah"
    var fajrVoice = "makkah_fajr"
    var volume = 0.8
    var preReminder = 10                         // minutes, 0 = off
    var smartPause = true
    var meetingSilent = true

    var khatmaOn = true
    var khatmaDays = 30
    var khatmaStart = Date()
    var khatmaRead = 0
    var khatmaCount = 0                          // finished khatmas
    var khatmaAfterPrayer = true

    var adhkarMorning = true
    var adhkarEvening = true
    var adhkarAfterPrayer = true
    var jumuah = true
    var khutbahBefore = 30
    var suhoorBefore = 45

    var launchAtLogin = true

    var deskOn = true
    var deskSize: DeskSize = .medium
    var deskOnTop = false
    var deskScale = 1.0         // free size of the desktop widget (0.6 ... 2)
    var autoUpdateCheck = true  // daily check for a new version on GitHub
    var panelScale = 1.0        // size of the window that opens from the menu bar (0.8 ... 1.5)

    var speakOn = true          // spoken announcement instead of the adhan (silent mode / meeting)
    var speakRepeats = 2
    var speakInMeeting = true
    var speakVolume = 0.6
    var speakTakbir = true      // start with the sheikh's first takbir

    init() {}

    func mode(_ p: Prayer) -> AlertMode { modes[String(p.rawValue)] ?? (p == .sunrise ? .off : .adhan) }
    mutating func setMode(_ m: AlertMode, for p: Prayer) { modes[String(p.rawValue)] = m }

    var effectiveMethod: CalcMethod { autoMethod ? CalcMethod.forCountry(countryCode) : method }

    func calcInput(ramadan: Bool) -> CalcInput? {
        guard let lat = latitude, let lon = longitude else { return nil }
        return CalcInput(latitude: lat, longitude: lon, method: effectiveMethod, school: school,
                         highLat: highLat, offsets: offsets.count == 6 ? offsets : [0, 0, 0, 0, 0, 0], ramadan: ramadan)
    }

    var khatma: KhatmaPlan { KhatmaPlan(days: khatmaDays, start: khatmaStart, lastRead: khatmaRead) }

    enum K: String, CodingKey {
        case autoLocation, latitude, longitude, placeName, countryCode, autoMethod, method, school, highLat, offsets,
             hijriOffset, latinDigits, use24h, modes, voice, fajrVoice, volume, preReminder, smartPause, meetingSilent,
             khatmaOn, khatmaDays, khatmaStart, khatmaRead, khatmaCount, khatmaAfterPrayer,
             adhkarMorning, adhkarEvening, adhkarAfterPrayer, jumuah, khutbahBefore, suhoorBefore, launchAtLogin,
             deskOn, deskSize, deskOnTop, deskScale, panelScale, autoUpdateCheck, speakOn, speakRepeats, speakInMeeting, speakVolume, speakTakbir
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: K.self)
        let d = Settings.blank
        func v<T: Decodable>(_ k: K, _ def: T) -> T {
            guard let x = try? c.decodeIfPresent(T.self, forKey: k) else { return def }
            return x
        }
        autoLocation = v(.autoLocation, d.autoLocation)
        latitude = try? c.decodeIfPresent(Double.self, forKey: .latitude)
        longitude = try? c.decodeIfPresent(Double.self, forKey: .longitude)
        placeName = v(.placeName, d.placeName)
        countryCode = try? c.decodeIfPresent(String.self, forKey: .countryCode)
        autoMethod = v(.autoMethod, d.autoMethod)
        method = v(.method, d.method)
        school = v(.school, d.school)
        highLat = v(.highLat, d.highLat)
        offsets = v(.offsets, d.offsets)
        hijriOffset = v(.hijriOffset, d.hijriOffset)
        latinDigits = v(.latinDigits, d.latinDigits)
        use24h = v(.use24h, d.use24h)
        modes = v(.modes, d.modes)
        voice = v(.voice, d.voice)
        fajrVoice = v(.fajrVoice, d.fajrVoice)
        volume = v(.volume, d.volume)
        preReminder = v(.preReminder, d.preReminder)
        smartPause = v(.smartPause, d.smartPause)
        meetingSilent = v(.meetingSilent, d.meetingSilent)
        khatmaOn = v(.khatmaOn, d.khatmaOn)
        khatmaDays = v(.khatmaDays, d.khatmaDays)
        khatmaStart = v(.khatmaStart, d.khatmaStart)
        khatmaRead = v(.khatmaRead, d.khatmaRead)
        khatmaCount = v(.khatmaCount, d.khatmaCount)
        khatmaAfterPrayer = v(.khatmaAfterPrayer, d.khatmaAfterPrayer)
        adhkarMorning = v(.adhkarMorning, d.adhkarMorning)
        adhkarEvening = v(.adhkarEvening, d.adhkarEvening)
        adhkarAfterPrayer = v(.adhkarAfterPrayer, d.adhkarAfterPrayer)
        jumuah = v(.jumuah, d.jumuah)
        khutbahBefore = v(.khutbahBefore, d.khutbahBefore)
        suhoorBefore = v(.suhoorBefore, d.suhoorBefore)
        launchAtLogin = v(.launchAtLogin, d.launchAtLogin)
        deskOn = v(.deskOn, d.deskOn)
        deskSize = v(.deskSize, d.deskSize)
        deskOnTop = v(.deskOnTop, d.deskOnTop)
        deskScale = min(2, max(0.6, v(.deskScale, d.deskScale)))
        panelScale = min(1.5, max(0.8, v(.panelScale, d.panelScale)))
        autoUpdateCheck = v(.autoUpdateCheck, d.autoUpdateCheck)
        speakOn = v(.speakOn, d.speakOn)
        speakRepeats = v(.speakRepeats, d.speakRepeats)
        speakInMeeting = v(.speakInMeeting, d.speakInMeeting)
        speakVolume = v(.speakVolume, d.speakVolume)
        speakTakbir = v(.speakTakbir, d.speakTakbir)
    }
    private static let blank = Settings()
}

/// Loads and saves settings. Never overwrites a file it could not read.
final class SettingsStore {
    let dir: URL
    var file: URL { dir.appendingPathComponent("settings.json") }
    private(set) var readOnlyBecauseBroken = false

    init(dir: URL = Paths.dataDir) {
        self.dir = dir
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        chmod(dir.path, 0o700)
    }

    func load() -> Settings {
        let fm = FileManager.default
        guard fm.fileExists(atPath: file.path) else { return Settings() }
        do {
            let data = try Data(contentsOf: file)
            let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
            return try dec.decode(Settings.self, from: data)
        } catch {
            // keep the broken file safe and do not write over it this run
            let aside = dir.appendingPathComponent("settings.unreadable-\(Int(Date().timeIntervalSince1970)).json")
            try? fm.copyItem(at: file, to: aside)
            readOnlyBecauseBroken = true
            Log.write("settings unreadable, copied to \(aside.lastPathComponent): \(error)")
            return restoreFromBackup() ?? Settings()
        }
    }

    func save(_ s: Settings) {
        if readOnlyBecauseBroken { return }
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601; enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? enc.encode(s) else { return }
        try? data.write(to: file, options: .atomic)
    }

    private func restoreFromBackup() -> Settings? {
        let bdir = dir.appendingPathComponent("Backups")
        guard let files = try? FileManager.default.contentsOfDirectory(at: bdir, includingPropertiesForKeys: nil) else { return nil }
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        for f in files.sorted(by: { $0.lastPathComponent > $1.lastPathComponent }) {
            if let d = try? Data(contentsOf: f), let s = try? dec.decode(Settings.self, from: d) {
                Log.write("restored settings from \(f.lastPathComponent)")
                return s
            }
        }
        return nil
    }

    /// one copy per day: 7 local, 30 on the external drive when it is mounted
    func dailyBackup() {
        guard FileManager.default.fileExists(atPath: file.path) else { return }
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"
        let name = "settings-\(f.string(from: Date())).json"
        var targets = [(dir.appendingPathComponent("Backups"), 7)]
        let ext = URL(fileURLWithPath: "/Volumes/Momen exte/Mac Mini/Basic/manus/Work/Azan/Backups")
        if ProcessInfo.processInfo.environment["AZAN_DATA"] == nil,
           FileManager.default.fileExists(atPath: ext.path) { targets.append((ext, 30)) }
        for (d, keep) in targets {
            try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
            let dest = d.appendingPathComponent(name)
            if !FileManager.default.fileExists(atPath: dest.path) { try? FileManager.default.copyItem(at: file, to: dest) }
            let all = ((try? FileManager.default.contentsOfDirectory(atPath: d.path)) ?? [])
                .filter { $0.hasPrefix("settings-") }.sorted()
            for old in all.dropLast(keep) { try? FileManager.default.removeItem(at: d.appendingPathComponent(old)) }
        }
    }
}

enum Log {
    static var muted = false
    static var url: URL { URL(fileURLWithPath: Paths.realHome + "/Library/Logs/Azan.log") }
    static func write(_ s: String) {
        if muted { return }
        let line = "\(ISO8601DateFormatter().string(from: Date())) \(s)\n"
        if let h = try? FileHandle(forWritingTo: url) {
            h.seekToEndOfFile(); h.write(line.data(using: .utf8)!); try? h.close()
            if let size = try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int, size > 512_000 {
                try? FileManager.default.removeItem(at: url)
            }
        } else {
            try? line.data(using: .utf8)!.write(to: url)
        }
    }
}
