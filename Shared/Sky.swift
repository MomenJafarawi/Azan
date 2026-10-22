import SwiftUI

/// The living sky: colours follow the real sun height at the user's location.
struct SkyLook {
    var top: Color
    var bottom: Color
    var text: Color
    var secondary: Color
    var gold: Color
    var stars: Double      // 0...1 opacity of stars
    var isDark: Bool

    var gradient: LinearGradient {
        LinearGradient(colors: [top, bottom], startPoint: .top, endPoint: .bottom)
    }

    static func rgb(_ r: Double, _ g: Double, _ b: Double) -> (Double, Double, Double) { (r / 255, g / 255, b / 255) }

    private typealias RGB = (Double, Double, Double)
    private struct Stop { let alt: Double; let top: RGB; let bottom: RGB }

    // morning: night → dawn pink → clear blue
    private static let morning: [Stop] = [
        Stop(alt: -90, top: rgb(8, 12, 32), bottom: rgb(22, 30, 64)),
        Stop(alt: -18, top: rgb(14, 18, 48), bottom: rgb(40, 38, 88)),
        Stop(alt: -10, top: rgb(46, 42, 104), bottom: rgb(150, 92, 140)),
        Stop(alt: -4, top: rgb(98, 96, 170), bottom: rgb(240, 160, 170)),
        Stop(alt: 2, top: rgb(132, 168, 222), bottom: rgb(252, 200, 170)),
        Stop(alt: 12, top: rgb(92, 160, 230), bottom: rgb(196, 222, 246)),
        Stop(alt: 35, top: rgb(46, 128, 222), bottom: rgb(150, 200, 244)),
        Stop(alt: 90, top: rgb(30, 110, 214), bottom: rgb(130, 190, 242)),
    ]
    // evening: clear blue → asr gold → maghrib orange → night
    private static let evening: [Stop] = [
        Stop(alt: -90, top: rgb(8, 12, 32), bottom: rgb(22, 30, 64)),
        Stop(alt: -18, top: rgb(12, 16, 44), bottom: rgb(34, 32, 76)),
        Stop(alt: -10, top: rgb(36, 32, 86), bottom: rgb(110, 58, 110)),
        Stop(alt: -4, top: rgb(70, 52, 120), bottom: rgb(214, 96, 84)),
        Stop(alt: 2, top: rgb(112, 92, 150), bottom: rgb(246, 140, 70)),
        Stop(alt: 12, top: rgb(86, 138, 200), bottom: rgb(246, 196, 120)),
        Stop(alt: 28, top: rgb(54, 128, 214), bottom: rgb(226, 214, 176)),
        Stop(alt: 90, top: rgb(30, 110, 214), bottom: rgb(130, 190, 242)),
    ]

    static func at(altitude a: Double, rising: Bool) -> SkyLook {
        let stops = rising ? morning : evening
        var lo = stops[0], hi = stops[stops.count - 1]
        for i in 0..<(stops.count - 1) where a >= stops[i].alt && a <= stops[i + 1].alt {
            lo = stops[i]; hi = stops[i + 1]
        }
        let t = hi.alt == lo.alt ? 0 : max(0, min(1, (a - lo.alt) / (hi.alt - lo.alt)))
        func mix(_ x: RGB, _ y: RGB) -> RGB { (x.0 + (y.0 - x.0) * t, x.1 + (y.1 - x.1) * t, x.2 + (y.2 - x.2) * t) }
        let top = mix(lo.top, hi.top), bottom = mix(lo.bottom, hi.bottom)
        // readable text: judge by the brightness of the middle of the gradient
        func lum(_ c: RGB) -> Double { 0.2126 * c.0 + 0.7152 * c.1 + 0.0722 * c.2 }
        let mid = (lum(top) + lum(bottom)) / 2
        let dark = mid < 0.55
        let stars = max(0, min(1, (-a - 6) / 10))
        return SkyLook(
            top: Color(red: top.0, green: top.1, blue: top.2),
            bottom: Color(red: bottom.0, green: bottom.1, blue: bottom.2),
            text: dark ? .white : Color(red: 0.08, green: 0.10, blue: 0.20),
            secondary: dark ? Color.white.opacity(0.72) : Color(red: 0.12, green: 0.14, blue: 0.26).opacity(0.72),
            gold: dark ? Color(red: 0.98, green: 0.80, blue: 0.42) : Color(red: 0.62, green: 0.42, blue: 0.06),
            stars: stars,
            isDark: dark)
    }

    /// "Luxury night": deep navy, cream text, gold. The chosen look for the whole app.
    static let luxury = SkyLook(
        top: Color(red: 0.035, green: 0.055, blue: 0.15),
        bottom: Color(red: 0.085, green: 0.11, blue: 0.27),
        text: Color(red: 0.97, green: 0.92, blue: 0.80),
        secondary: Color(red: 0.80, green: 0.74, blue: 0.60),
        gold: Color(red: 0.92, green: 0.76, blue: 0.40),
        stars: 1,
        isDark: true)

    static func now(lat: Double, lon: Double, date: Date = Date()) -> SkyLook { luxury }

    /// the old time-of-day sky (kept for reference / tests)
    static func timeOfDay(lat: Double, lon: Double, date: Date = Date()) -> SkyLook {
        let a = PrayerCalc.sunAltitude(lat: lat, lon: lon, at: date)
        let b = PrayerCalc.sunAltitude(lat: lat, lon: lon, at: date.addingTimeInterval(600))
        return at(altitude: a, rising: b > a)
    }
}

/// Tiny fixed star field (deterministic so it does not jump between redraws).
struct StarField: View {
    var opacity: Double
    var body: some View {
        Canvas { ctx, size in
            var seed: UInt64 = 0x9E3779B97F4A7C15
            func rnd() -> Double {
                seed ^= seed << 13; seed ^= seed >> 7; seed ^= seed << 17
                return Double(seed % 10_000) / 10_000
            }
            for _ in 0..<60 {
                let x = rnd() * size.width, y = rnd() * size.height * 0.75
                let r = 0.4 + rnd() * 1.1
                let o = (0.35 + rnd() * 0.65) * opacity
                ctx.fill(Path(ellipseIn: CGRect(x: x, y: y, width: r * 2, height: r * 2)), with: .color(.white.opacity(o)))
            }
        }
        .allowsHitTesting(false)
        .opacity(opacity > 0.01 ? 1 : 0)
    }
}

struct SkyBackground: View {
    var look: SkyLook
    var body: some View {
        ZStack {
            LinearGradient(colors: [look.top, look.bottom], startPoint: .topTrailing, endPoint: .bottomLeading)
            RadialGradient(colors: [look.gold.opacity(0.10), .clear], center: .topLeading, startRadius: 0, endRadius: 220)
            StarField(opacity: look.stars * 0.8)
        }
    }
}
