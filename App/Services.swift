import AppKit
import AVFoundation
import CoreAudio
import CoreLocation
import ApplicationServices

// MARK: - Spoken announcement (Arabic voice, e.g. "حان الآن موعد أذان الفجر")

final class Announcer: NSObject, AVAudioPlayerDelegate {
    private let synth = AVSpeechSynthesizer()
    private var clip: AVAudioPlayer?
    private var pending: (() -> Void)?
    private var stopWork: DispatchWorkItem?

    /// end of the second "الله أكبر" (first pair) in each recording, in seconds, measured from the audio envelope
    static let takbirEnd: [String: Double] = [
        "makkah": 14.4, "makkah_fajr": 10.9, "madinah": 9.8, "madinah_fajr": 14.4,
        "alafasy": 15.6, "alafasy_fajr": 17.9, "aqsa": 10.7, "abdulbasit": 10.3,
    ]

    /// name of the bundled recording (Resources/Speech/<key>.m4a), recorded with Majed on the Mac
    static func key(for p: Prayer, ramadan: Bool) -> String {
        if p == .maghrib && ramadan { return "iftar" }
        return ["fajr", "sunrise", "dhuhr", "asr", "maghrib", "isha"][p.rawValue]
    }
    static func speechURL(_ key: String) -> URL? {
        Res.url("Speech/\(key).m4a")
    }
    private var speech: [AVAudioPlayer] = []

    static func text(for p: Prayer, ramadan: Bool) -> String {
        if p == .sunrise { return "حان الآن وقت الشروق" }
        if p == .maghrib && ramadan { return "حان الآن موعد الإفطار، أذان المغرب" }
        return "حان الآن موعد أذان \(p.arabic)"
    }

    /// best Arabic voice installed: premium, then enhanced (e.g. Majed Enhanced), then the default
    static var voice: AVSpeechSynthesisVoice? {
        let ar = AVSpeechSynthesisVoice.speechVoices().filter { $0.language.hasPrefix("ar") }
        return ar.first { $0.quality == .premium } ?? ar.first { $0.quality == .enhanced }
            ?? AVSpeechSynthesisVoice(language: "ar-001") ?? ar.first
    }
    static var hasEnhanced: Bool { voice.map { $0.quality != .default } ?? false }

    /// takbir from the chosen sheikh, then the sentence `times` times
    func announce(_ text: String, key: String? = nil, voiceID: String?, times: Int, volume: Double) {
        stop()
        let speakAll: () -> Void = { [weak self] in
            if let k = key, let u = Announcer.speechURL(k) { self?.play(u, times: times, volume: volume) }
            else { self?.say(text, times: times, volume: volume) }
        }
        guard let id = voiceID, let url = AdhanPlayer.url(id), let p = try? AVAudioPlayer(contentsOf: url) else { speakAll(); return }
        let end = Announcer.takbirEnd[id] ?? 8
        Log.write("announce: start \(id) end=\(end)")
        p.volume = Float(volume)
        p.delegate = self
        p.prepareToPlay(); p.play()
        clip = p
        pending = speakAll
        // fade out at the end of the takbir, then speak
        let w = DispatchWorkItem { [weak self] in
            p.setVolume(0, fadeDuration: 0.6)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.65) { self?.finishClip() }
        }
        stopWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + max(1, end - 0.3), execute: w)
    }

    private func finishClip() {
        clip?.stop(); clip = nil
        let next = pending; pending = nil
        next?()
    }
    func audioPlayerDidFinishPlaying(_ p: AVAudioPlayer, successfully flag: Bool) { if p === clip { stopWork?.cancel(); finishClip() } }

    /// plays the bundled recording `times` times with a short gap (works on any Mac, no voice needed)
    private func play(_ url: URL, times: Int, volume: Double) {
        Log.write("announce: play \(url.lastPathComponent) x\(times)")
        speech = []
        var at: TimeInterval = 0.5
        for _ in 0..<max(1, min(5, times)) {
            guard let p = try? AVAudioPlayer(contentsOf: url) else { break }
            p.volume = Float(volume)
            p.prepareToPlay()
            p.play(atTime: p.deviceCurrentTime + at)
            speech.append(p)
            at += p.duration + 1.0
        }
    }

    func say(_ text: String, times: Int, volume: Double) {
        Log.write("announce: say '\(text)' x\(times) voice=\(Announcer.voice?.name ?? "nil")")
        for i in 0..<max(1, min(5, times)) {
            let u = AVSpeechUtterance(string: text)
            u.voice = Announcer.voice
            u.rate = AVSpeechUtteranceDefaultSpeechRate * 0.9
            u.volume = Float(volume)
            u.preUtteranceDelay = i == 0 ? 0.5 : 1.2
            synth.speak(u)
        }
    }

    func stop() {
        stopWork?.cancel(); pending = nil
        clip?.stop(); clip = nil
        speech.forEach { $0.stop() }; speech = []
        synth.stopSpeaking(at: .immediate)
    }
}

// MARK: - Location

final class LocationService: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private let geocoder = CLGeocoder()
    var onUpdate: ((CLLocation, String, String?) -> Void)?
    var onDenied: (() -> Void)?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    func refresh() {
        switch manager.authorizationStatus {
        case .notDetermined: manager.requestWhenInUseAuthorization()
        case .denied, .restricted: onDenied?()
        default: manager.requestLocation()
        }
    }

    func locationManagerDidChangeAuthorization(_ m: CLLocationManager) {
        switch m.authorizationStatus {
        case .authorized, .authorizedAlways: m.requestLocation()
        case .denied, .restricted: onDenied?()
        default: break
        }
    }

    func locationManager(_ m: CLLocationManager, didUpdateLocations locs: [CLLocation]) {
        guard let loc = locs.last else { return }
        geocoder.reverseGeocodeLocation(loc, preferredLocale: Locale(identifier: "ar")) { [weak self] marks, _ in
            let p = marks?.first
            let name = p?.locality ?? p?.administrativeArea ?? p?.country ?? ""
            DispatchQueue.main.async { self?.onUpdate?(loc, name, p?.isoCountryCode) }
        }
    }

    func locationManager(_ m: CLLocationManager, didFailWithError error: Error) {
        Log.write("location error: \(error.localizedDescription)")
    }

    /// manual city search
    func search(_ text: String, done: @escaping ([(String, String?, CLLocation)]) -> Void) {
        geocoder.geocodeAddressString(text, in: nil, preferredLocale: Locale(identifier: "ar")) { marks, _ in
            let r = (marks ?? []).compactMap { p -> (String, String?, CLLocation)? in
                guard let l = p.location else { return nil }
                let name = [p.locality, p.country].compactMap { $0 }.joined(separator: "، ")
                return (name.isEmpty ? text : name, p.isoCountryCode, l)
            }
            DispatchQueue.main.async { done(r) }
        }
    }
}

// MARK: - Adhan sound

final class AdhanPlayer: NSObject, AVAudioPlayerDelegate {
    private var player: AVAudioPlayer?
    var onFinish: (() -> Void)?
    var isPlaying: Bool { player?.isPlaying ?? false }

    static func url(_ id: String) -> URL? {
        Res.url("Sounds/\(id).mp3")
    }

    func play(_ id: String, volume: Double, fadeIn: Bool = true) {
        stop(notify: false)
        guard let u = AdhanPlayer.url(id), let p = try? AVAudioPlayer(contentsOf: u) else {
            Log.write("sound missing: \(id)"); onFinish?(); return
        }
        p.delegate = self
        p.volume = fadeIn ? 0 : Float(volume)
        p.prepareToPlay()
        p.play()
        if fadeIn { p.setVolume(Float(volume), fadeDuration: 2.5) }
        player = p
    }

    func stop(notify: Bool = true) {
        guard let p = player else { return }
        player = nil
        if p.isPlaying {
            p.setVolume(0, fadeDuration: 0.6)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { p.stop() }
        }
        if notify { onFinish?() }
    }

    func audioPlayerDidFinishPlaying(_ p: AVAudioPlayer, successfully flag: Bool) {
        if p === player { player = nil; onFinish?() }
    }
}

// MARK: - Smart pause (meetings and media)

enum AudioState {
    private static func ids(_ selector: AudioObjectPropertySelector, of obj: AudioObjectID = AudioObjectID(kAudioObjectSystemObject)) -> [AudioObjectID] {
        var addr = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(obj, &addr, 0, nil, &size) == noErr, size > 0 else { return [] }
        var list = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(obj, &addr, 0, nil, &size, &list) == noErr else { return [] }
        return list
    }
    private static func u32(_ obj: AudioObjectID, _ sel: AudioObjectPropertySelector, scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> UInt32? {
        var addr = AudioObjectPropertyAddress(mSelector: sel, mScope: scope, mElement: kAudioObjectPropertyElementMain)
        var v: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(obj, &addr, 0, nil, &size, &v) == noErr ? v : nil
    }
    private static func hasInput(_ dev: AudioObjectID) -> Bool {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreams, mScope: kAudioDevicePropertyScopeInput, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        return AudioObjectGetPropertyDataSize(dev, &addr, 0, nil, &size) == noErr && size > 0
    }

    /// true while any app records from a microphone (a call or meeting)
    static func micInUse() -> Bool {
        for dev in ids(kAudioHardwarePropertyDevices) where hasInput(dev) {
            if u32(dev, kAudioDevicePropertyDeviceIsRunningSomewhere) == 1 { return true }
        }
        return false
    }

    /// true while another app is sending sound to the speakers
    static func othersPlaying() -> Bool {
        let me = getpid()
        for proc in ids(kAudioHardwarePropertyProcessObjectList) {
            guard u32(proc, kAudioProcessPropertyIsRunningOutput) == 1 else { continue }
            var addr = AudioObjectPropertyAddress(mSelector: kAudioProcessPropertyPID, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
            var pid: pid_t = 0
            var size = UInt32(MemoryLayout<pid_t>.size)
            if AudioObjectGetPropertyData(proc, &addr, 0, nil, &size, &pid) == noErr, pid != me, pid > 0 {
                // ignore system sound daemons
                let name = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier ?? ""
                if name.hasPrefix("com.apple.") && !["com.apple.Music", "com.apple.TV", "com.apple.Safari", "com.apple.podcasts", "com.apple.QuickTimePlayerX"].contains(name) { continue }
                if name.isEmpty { continue }
                return true
            }
        }
        return false
    }
}

enum MediaKeys {
    static var trusted: Bool { AXIsProcessTrusted() }
    static func askForPermission() {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)
    }
    /// press the play/pause media key once
    static func playPause() {
        let key = 16 // NX_KEYTYPE_PLAY
        for down in [true, false] {
            let flags = NSEvent.ModifierFlags(rawValue: down ? 0xA00 : 0xB00)
            let data1 = (key << 16) | ((down ? 0xA : 0xB) << 8)
            if let ev = NSEvent.otherEvent(with: .systemDefined, location: .zero, modifierFlags: flags, timestamp: 0,
                                           windowNumber: 0, context: nil, subtype: 8, data1: data1, data2: -1) {
                ev.cgEvent?.post(tap: .cghidEventTap)
            }
        }
    }
}

// MARK: - Launch at login (LaunchAgent, same as the other apps)

enum LoginItem {
    static var plist: URL { URL(fileURLWithPath: Paths.realHome + "/Library/LaunchAgents/com.momen.azan.plist") }
    static func set(_ on: Bool) {
        if !on { try? FileManager.default.removeItem(at: plist); return }
        let exe = Bundle.main.executableURL?.path ?? "/Applications/Azan.app/Contents/MacOS/Azan"
        guard exe.hasPrefix("/Applications/") else { return }
        let dict: [String: Any] = ["Label": "com.momen.azan", "ProgramArguments": [exe], "RunAtLoad": true,
                                   "KeepAlive": ["SuccessfulExit": false], "ProcessType": "Interactive"]
        try? FileManager.default.createDirectory(at: plist.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let d = try? PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0) {
            try? d.write(to: plist)
        }
    }
}
