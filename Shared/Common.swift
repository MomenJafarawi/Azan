import SwiftUI
import CoreText

// Things both the app and the widget need.

enum Paths {
    /// real home folder, also from inside the sandboxed widget
    static var realHome: String {
        if let pw = getpwuid(getuid()), let dir = pw.pointee.pw_dir { return String(cString: dir) }
        return NSHomeDirectory()
    }
    static var dataDir: URL {
        if let custom = ProcessInfo.processInfo.environment["AZAN_DATA"], !custom.isEmpty {
            return URL(fileURLWithPath: custom, isDirectory: true)
        }
        return URL(fileURLWithPath: realHome + "/Library/Application Support/Azan", isDirectory: true)
    }
    static var widgetFile: URL { dataDir.appendingPathComponent("widget.json") }
}

/// Small snapshot the app writes for the widget.
struct WidgetSnapshot: Codable {
    var input: CalcInput
    var placeName: String
    var hijriOffset: Int
    var latinDigits: Bool
    var use24h: Bool
    var khatmaOn: Bool
    var khatmaRead: Int          // last page read
    var khatmaTarget: Int        // page that should be reached by end of today
    var updated: Date

    static func load() -> WidgetSnapshot? {
        guard let d = try? Data(contentsOf: Paths.widgetFile) else { return nil }
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        return try? dec.decode(WidgetSnapshot.self, from: d)
    }
}

enum Fmt {
    static func locale(latin: Bool) -> Locale { Locale(identifier: latin ? "ar@numbers=latn" : "ar@numbers=arab") }

    static func num(_ n: Int, latin: Bool) -> String {
        let f = NumberFormatter()
        f.locale = locale(latin: latin)
        return f.string(from: NSNumber(value: n)) ?? "\(n)"
    }

    static func time(_ d: Date, latin: Bool, use24h: Bool) -> String {
        let f = DateFormatter()
        f.locale = locale(latin: latin)
        f.timeZone = .current
        f.dateFormat = use24h ? "HH:mm" : "h:mm a"
        return f.string(from: d)
    }

    /// "٤٥ د" / "١ س ٢٠ د"
    static func countdown(_ seconds: TimeInterval, latin: Bool) -> String {
        let m = max(0, Int((seconds / 60).rounded(.up)))
        if m < 60 { return "\(num(m, latin: latin)) د" }
        let h = m / 60, r = m % 60
        return r == 0 ? "\(num(h, latin: latin)) س" : "\(num(h, latin: latin)) س \(num(r, latin: latin)) د"
    }

    static func countdownLong(_ seconds: TimeInterval, latin: Bool) -> String {
        let m = max(0, Int((seconds / 60).rounded(.up)))
        func mins(_ x: Int) -> String {
            switch x {
            case 1: return "دقيقة"
            case 2: return "دقيقتين"
            case 3...10: return "\(num(x, latin: latin)) دقائق"
            default: return "\(num(x, latin: latin)) دقيقة"
            }
        }
        if m < 60 { return "بعد \(mins(m))" }
        let h = m / 60, r = m % 60
        let hs = h == 1 ? "ساعة" : (h == 2 ? "ساعتين" : "\(num(h, latin: latin)) ساعات")
        return r == 0 ? "بعد \(hs)" : "بعد \(hs) و\(mins(r))"
    }

    static func hijriDate(_ d: Date, offset: Int) -> DateComponents {
        let cal = Calendar(identifier: .islamicUmmAlQura)
        return cal.dateComponents([.year, .month, .day, .weekday], from: d.addingTimeInterval(Double(offset) * 86400))
    }

    static func hijri(_ d: Date, offset: Int, latin: Bool, withYear: Bool = true) -> String {
        let f = DateFormatter()
        f.locale = locale(latin: latin)
        f.calendar = Calendar(identifier: .islamicUmmAlQura)
        f.dateFormat = withYear ? "d MMMM y" : "d MMMM"
        return f.string(from: d.addingTimeInterval(Double(offset) * 86400)) + (withYear ? " هـ" : "")
    }

    static func gregorian(_ d: Date, latin: Bool) -> String {
        let f = DateFormatter()
        f.locale = locale(latin: latin)
        f.dateFormat = "EEEE d MMMM"
        return f.string(from: d)
    }

    static func isRamadan(_ d: Date, offset: Int) -> Bool { hijriDate(d, offset: offset).month == 9 }
}

enum Quran {
    static let pages = 604
    /// start page of each surah in the Madani mushaf (checked against api.quran.com)
    static let surahStart: [Int] = [1, 2, 50, 77, 106, 128, 151, 177, 187, 208, 221, 235, 249, 255, 262, 267, 282, 293, 305, 312, 322, 332, 342, 350, 359, 367, 377, 385, 396, 404, 411, 415, 418, 428, 434, 440, 446, 453, 458, 467, 477, 483, 489, 496, 499, 502, 507, 511, 515, 518, 520, 523, 526, 528, 531, 534, 537, 542, 545, 549, 551, 553, 554, 556, 558, 560, 562, 564, 566, 568, 570, 572, 574, 575, 577, 578, 580, 582, 583, 585, 586, 587, 587, 589, 590, 591, 591, 592, 593, 594, 595, 595, 596, 596, 597, 597, 598, 598, 599, 599, 600, 600, 601, 601, 601, 602, 602, 602, 603, 603, 603, 604, 604, 604]
    static let surahNames: [String] = "الفاتحة|البقرة|آل عمران|النساء|المائدة|الأنعام|الأعراف|الأنفال|التوبة|يونس|هود|يوسف|الرعد|إبراهيم|الحجر|النحل|الإسراء|الكهف|مريم|طه|الأنبياء|الحج|المؤمنون|النور|الفرقان|الشعراء|النمل|القصص|العنكبوت|الروم|لقمان|السجدة|الأحزاب|سبأ|فاطر|يس|الصافات|ص|الزمر|غافر|فصلت|الشورى|الزخرف|الدخان|الجاثية|الأحقاف|محمد|الفتح|الحجرات|ق|الذاريات|الطور|النجم|القمر|الرحمن|الواقعة|الحديد|المجادلة|الحشر|الممتحنة|الصف|الجمعة|المنافقون|التغابن|الطلاق|التحريم|الملك|القلم|الحاقة|المعارج|نوح|الجن|المزمل|المدثر|القيامة|الإنسان|المرسلات|النبأ|النازعات|عبس|التكوير|الانفطار|المطففين|الانشقاق|البروج|الطارق|الأعلى|الغاشية|الفجر|البلد|الشمس|الليل|الضحى|الشرح|التين|العلق|القدر|البينة|الزلزلة|العاديات|القارعة|التكاثر|العصر|الهمزة|الفيل|قريش|الماعون|الكوثر|الكافرون|النصر|المسد|الإخلاص|الفلق|الناس".components(separatedBy: "|")

    /// surah that is being read on a page (the last one that starts on or before it)
    static func surah(onPage p: Int) -> String {
        var idx = 0
        for (i, s) in surahStart.enumerated() where s <= p { idx = i }
        return surahNames[idx]
    }
    static func juz(ofPage p: Int) -> Int { p < 22 ? 1 : min(30, (p - 2) / 20 + 1) }
    static func url(page: Int) -> URL { URL(string: "https://quran.com/page/\(max(1, min(pages, page)))")! }
}

/// Khatma plan arithmetic (pure, so it can be self-tested).
struct KhatmaPlan {
    var days: Int
    var start: Date
    var lastRead: Int

    var perDay: Double { Double(Quran.pages) / Double(max(1, days)) }

    func dayIndex(_ now: Date) -> Int {
        let cal = Calendar.current
        let d = cal.dateComponents([.day], from: cal.startOfDay(for: start), to: cal.startOfDay(for: now)).day ?? 0
        return max(1, d + 1)
    }
    /// page you should reach by the end of today
    func target(_ now: Date) -> Int { min(Quran.pages, Int((perDay * Double(dayIndex(now))).rounded(.up))) }
    /// pages to read after one prayer (the day split over five prayers)
    var chunk: Int { max(1, Int((perDay / 5).rounded(.up))) }
    func nextPortion(_ now: Date) -> ClosedRange<Int>? {
        if lastRead >= Quran.pages { return nil }
        let from = lastRead + 1
        let to = min(Quran.pages, lastRead + chunk)
        return from...to
    }
    var finished: Bool { lastRead >= Quran.pages }
    func behind(_ now: Date) -> Int { max(0, target(now) - lastRead) }
}

enum AppFont {
    static func register(bundle: Bundle) {
        for name in ["Amiri-Regular", "Amiri-Bold"] {
            if let u = bundle.url(forResource: name, withExtension: "ttf") {
                CTFontManagerRegisterFontsForURL(u as CFURL, .process, nil)
            }
        }
    }
    static var hasAmiri: Bool { NSFont(name: "Amiri-Regular", size: 12) != nil }
    static func naskh(_ size: CGFloat, bold: Bool = false) -> Font {
        if hasAmiri { return .custom(bold ? "Amiri-Bold" : "Amiri-Regular", size: size) }
        return .system(size: size, weight: bold ? .bold : .regular)
    }
}
