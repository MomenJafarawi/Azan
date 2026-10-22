import Foundation

// Prayer time math (same astronomy as praytimes.org / adhan libraries).
// Times are computed in UTC hours and turned into real Dates, so summer/winter time
// is handled by the system time zone when they are shown.

enum Prayer: Int, CaseIterable, Codable {
    case fajr, sunrise, dhuhr, asr, maghrib, isha

    var arabic: String {
        switch self {
        case .fajr: return "الفجر"
        case .sunrise: return "الشروق"
        case .dhuhr: return "الظهر"
        case .asr: return "العصر"
        case .maghrib: return "المغرب"
        case .isha: return "العشاء"
        }
    }
    var isPrayer: Bool { self != .sunrise }
    var symbol: String {
        switch self {
        case .fajr: return "sun.haze"
        case .sunrise: return "sunrise"
        case .dhuhr: return "sun.max"
        case .asr: return "sun.min"
        case .maghrib: return "sunset"
        case .isha: return "moon.stars"
        }
    }
}

enum CalcMethod: String, CaseIterable, Codable {
    case mwl, ummAlQura, diyanet, egyptian, jordan, dubai, gulf, kuwait, isna, karachi, singapore, morocco, tunisia, france, russia

    var arabic: String {
        switch self {
        case .mwl: return "رابطة العالم الإسلامي"
        case .ummAlQura: return "أم القرى (مكة)"
        case .diyanet: return "الشؤون الدينية التركية"
        case .egyptian: return "الهيئة المصرية العامة للمساحة"
        case .jordan: return "وزارة الأوقاف الأردنية"
        case .dubai: return "دبي"
        case .gulf: return "قطر والخليج"
        case .kuwait: return "الكويت"
        case .isna: return "أمريكا الشمالية (ISNA)"
        case .karachi: return "جامعة العلوم الإسلامية بكراتشي"
        case .singapore: return "سنغافورة وماليزيا وإندونيسيا"
        case .morocco: return "المغرب"
        case .tunisia: return "تونس"
        case .france: return "فرنسا (UOIF)"
        case .russia: return "روسيا"
        }
    }

    /// fajr angle, isha angle (nil when isha is minutes after maghrib)
    var fajrAngle: Double {
        switch self {
        case .mwl, .diyanet, .jordan, .gulf, .kuwait, .karachi, .tunisia: return 18
        case .ummAlQura: return 18.5
        case .egyptian: return 19.5
        case .dubai: return 18.2
        case .isna: return 15
        case .singapore: return 20
        case .morocco: return 19
        case .france: return 12
        case .russia: return 16
        }
    }
    var ishaAngle: Double? {
        switch self {
        case .mwl, .diyanet, .morocco: return 17
        case .ummAlQura, .gulf: return nil
        case .egyptian: return 17.5
        case .jordan, .karachi, .tunisia, .singapore: return 18
        case .dubai: return 18.2
        case .kuwait: return 17.5
        case .isna: return 15
        case .france: return 12
        case .russia: return 15
        }
    }
    var ishaMinutes: Double { self == .ummAlQura || self == .gulf ? 90 : 0 }

    /// built-in minute adjustments [fajr, sunrise, dhuhr, asr, maghrib, isha]
    var builtInOffsets: [Double] {
        switch self {
        case .diyanet: return [0, -7, 5, 4, 7, 0]
        case .dubai: return [0, -3, 3, 3, 3, 0]
        case .singapore: return [0, 0, 1, 0, 0, 0]
        case .jordan: return [0, 0, 0, 0, 5, 0]
        case .morocco: return [0, -3, 5, 0, 5, 0]
        default: return [0, 0, 0, 0, 0, 0]
        }
    }

    static func forCountry(_ code: String?) -> CalcMethod {
        switch (code ?? "").uppercased() {
        case "SA", "YE": return .ummAlQura
        case "TR": return .diyanet
        case "EG", "SY", "LB", "IQ", "SD", "LY": return .egyptian
        case "JO", "PS": return .jordan
        case "AE": return .dubai
        case "QA", "BH", "OM": return .gulf
        case "KW": return .kuwait
        case "US", "CA": return .isna
        case "PK", "IN", "BD", "AF": return .karachi
        case "MY", "SG", "BN", "ID": return .singapore
        case "MA": return .morocco
        case "TN": return .tunisia
        case "FR": return .france
        case "RU": return .russia
        default: return .mwl   // Germany and most of Europe
        }
    }
}

enum AsrSchool: String, CaseIterable, Codable {
    case shafi, hanafi
    var arabic: String { self == .shafi ? "الجمهور (شافعي، مالكي، حنبلي)" : "الحنفي" }
}

enum HighLatRule: String, CaseIterable, Codable {
    case auto, middleOfNight, seventhOfNight, angleBased, none
    var arabic: String {
        switch self {
        case .auto: return "تلقائي (مستحسن)"
        case .middleOfNight: return "منتصف الليل"
        case .seventhOfNight: return "سُبع الليل"
        case .angleBased: return "حسب الزاوية"
        case .none: return "بدون"
        }
    }
}

struct CalcInput: Codable, Equatable {
    var latitude: Double
    var longitude: Double
    var method: CalcMethod
    var school: AsrSchool
    var highLat: HighLatRule
    /// user minute adjustments [fajr, sunrise, dhuhr, asr, maghrib, isha]
    var offsets: [Double]
    var ramadan: Bool = false
}

struct DayTimes {
    var times: [Prayer: Date]
    func time(_ p: Prayer) -> Date { times[p] ?? Date.distantFuture }
}

enum PrayerCalc {
    private static func dsin(_ d: Double) -> Double { sin(d * .pi / 180) }
    private static func dcos(_ d: Double) -> Double { cos(d * .pi / 180) }
    private static func dtan(_ d: Double) -> Double { tan(d * .pi / 180) }
    private static func darcsin(_ x: Double) -> Double { asin(x) * 180 / .pi }
    private static func darccos(_ x: Double) -> Double { acos(x) * 180 / .pi }
    private static func darctan2(_ y: Double, _ x: Double) -> Double { atan2(y, x) * 180 / .pi }
    private static func darccot(_ x: Double) -> Double { atan(1 / x) * 180 / .pi }
    private static func fix(_ a: Double, _ b: Double) -> Double { let r = a - b * floor(a / b); return r < 0 ? r + b : r }

    static func julian(_ y: Int, _ m: Int, _ d: Int) -> Double {
        var y = y, m = m
        if m <= 2 { y -= 1; m += 12 }
        let a = floor(Double(y) / 100)
        let b = 2 - a + floor(a / 4)
        return floor(365.25 * Double(y + 4716)) + floor(30.6001 * Double(m + 1)) + Double(d) + b - 1524.5
    }

    /// declination (deg) and equation of time (hours)
    static func sunPosition(_ jd: Double) -> (decl: Double, eqt: Double) {
        let d = jd - 2451545.0
        let g = fix(357.529 + 0.98560028 * d, 360)
        let q = fix(280.459 + 0.98564736 * d, 360)
        let l = fix(q + 1.915 * dsin(g) + 0.020 * dsin(2 * g), 360)
        let e = 23.439 - 0.00000036 * d
        let ra = fix(darctan2(dcos(e) * dsin(l), dcos(l)) / 15, 24)
        let eqt = q / 15 - fix(ra, 24)
        let decl = darcsin(dsin(e) * dsin(l))
        // keep eqt in a sane range
        var eq = eqt
        if eq > 12 { eq -= 24 }
        if eq < -12 { eq += 24 }
        return (decl, eq)
    }

    /// Compute the day's times. `day` is any moment on the wanted local date in `tz`.
    static func compute(_ input: CalcInput, day: Date, tz: TimeZone = .current) -> DayTimes {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        let c = cal.dateComponents([.year, .month, .day], from: day)
        let (y, m, d) = (c.year!, c.month!, c.day!)
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let base = utc.date(from: DateComponents(year: y, month: m, day: d))!
        let jd0 = julian(y, m, d) - input.longitude / 360
        let lat = input.latitude
        let lng = input.longitude

        // times in local solar hours, refined twice
        func midDay(_ t: Double) -> Double { fix(12 - sunPosition(jd0 + t / 24).eqt, 24) }
        func angleTime(_ angle: Double, _ t: Double, ccw: Bool) -> Double {
            let decl = sunPosition(jd0 + t / 24).decl
            let noon = midDay(t)
            let arg = (-dsin(angle) - dsin(decl) * dsin(lat)) / (dcos(decl) * dcos(lat))
            if arg < -1 || arg > 1 { return .nan }
            let h = darccos(arg) / 15
            return noon + (ccw ? -h : h)
        }
        func asrTime(_ factor: Double, _ t: Double) -> Double {
            let decl = sunPosition(jd0 + t / 24).decl
            let angle = -darccot(factor + dtan(abs(lat - decl)))
            return angleTime(angle, t, ccw: false)
        }

        let asrFactor: Double = input.school == .hanafi ? 2 : 1
        var t: [Double] = [5, 6, 12, 13, 18, 18, 18] // fajr, sunrise, dhuhr, asr, sunset, maghrib, isha
        for _ in 0..<2 {
            let f = t.map { $0.isNaN ? 12 : $0 }
            let ishaA = input.method.ishaAngle ?? 18
            t = [
                angleTime(input.method.fajrAngle, f[0], ccw: true),
                angleTime(0.833, f[1], ccw: true),
                midDay(f[2]),
                asrTime(asrFactor, f[3]),
                angleTime(0.833, f[4], ccw: false),
                angleTime(0.833, f[5], ccw: false),
                angleTime(ishaA, f[6], ccw: false),
            ]
        }
        // to UTC hours
        t = t.map { $0 - lng / 15 }
        var fajr = t[0], sunrise = t[1], dhuhr = t[2], asr = t[3], sunset = t[4], isha = t[6]
        if input.method.ishaAngle == nil {
            isha = sunset + (input.ramadan && input.method == .ummAlQura ? 120 : input.method.ishaMinutes) / 60
        }

        // high latitude safety (fajr/isha must stay inside a share of the night)
        var rule = input.highLat
        if rule == .auto { rule = abs(lat) > 48 ? .seventhOfNight : .middleOfNight }
        if rule != .none, !sunrise.isNaN, !sunset.isNaN {
            let night = 24 - (sunset - sunrise)
            func portion(_ angle: Double) -> Double {
                switch rule {
                case .middleOfNight: return night / 2
                case .seventhOfNight: return night / 7
                case .angleBased: return angle / 60 * night
                default: return night / 2
                }
            }
            let safeFajr = sunrise - portion(input.method.fajrAngle)
            if fajr.isNaN || fajr < safeFajr { fajr = safeFajr }
            if input.method.ishaAngle != nil {
                let safeIsha = sunset + portion(input.method.ishaAngle!)
                if isha.isNaN || isha > safeIsha { isha = safeIsha }
            }
        }

        let builtIn = input.method.builtInOffsets
        let user = input.offsets.count == 6 ? input.offsets : [0, 0, 0, 0, 0, 0]
        let raw = [fajr, sunrise, dhuhr, asr, sunset, isha]
        var out: [Prayer: Date] = [:]
        for p in Prayer.allCases {
            let h = raw[p.rawValue]
            if h.isNaN { continue }
            let minutes = (h * 60 + builtIn[p.rawValue] + user[p.rawValue]).rounded()
            out[p] = base.addingTimeInterval(minutes * 60)
        }
        return DayTimes(times: out)
    }

    /// Sun altitude in degrees at a moment (used for the living sky colours).
    static func sunAltitude(lat: Double, lon: Double, at date: Date) -> Double {
        let jd = date.timeIntervalSince1970 / 86400 + 2440587.5
        let (decl, eqt) = sunPosition(jd)
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let c = utc.dateComponents([.hour, .minute, .second], from: date)
        let hours = Double(c.hour!) + Double(c.minute!) / 60 + Double(c.second!) / 3600
        let solar = hours + lon / 15 + eqt
        let ha = (solar - 12) * 15
        return darcsin(dsin(lat) * dsin(decl) + dcos(lat) * dcos(decl) * dcos(ha))
    }
}

/// What comes next, looking across today and tomorrow.
struct PrayerSchedule {
    let input: CalcInput
    let tz: TimeZone

    func day(_ date: Date) -> DayTimes { PrayerCalc.compute(input, day: date, tz: tz) }

    /// next event (including sunrise) after `now`
    func next(after now: Date, includeSunrise: Bool = true) -> (Prayer, Date) {
        for offset in 0...2 {
            let d = now.addingTimeInterval(Double(offset) * 86400)
            let dt = day(d)
            for p in Prayer.allCases where includeSunrise || p.isPrayer {
                if let t = dt.times[p], t > now { return (p, t) }
            }
        }
        return (.fajr, now.addingTimeInterval(86400))
    }

    /// the event before `now`
    func previous(before now: Date) -> (Prayer, Date) {
        for offset in 0...2 {
            let d = now.addingTimeInterval(-Double(offset) * 86400)
            let dt = day(d)
            for p in Prayer.allCases.reversed() {
                if let t = dt.times[p], t <= now { return (p, t) }
            }
        }
        return (.isha, now.addingTimeInterval(-3600))
    }
}
