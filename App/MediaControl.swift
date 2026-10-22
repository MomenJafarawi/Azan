import AppKit
import CoreAudio

/// Pauses what is *really* playing before the adhan and resumes exactly that afterwards.
/// Never presses play/pause unless it is sure something is audible (a paused YouTube tab
/// keeps its audio output open but silent, and must not be started).
struct PausedMedia {
    var apps: [String] = []        // bundle ids paused by AppleScript (Music, Spotify)
    var keyToggled = false         // play/pause key pressed for an audible app (browser etc.)
    var isEmpty: Bool { apps.isEmpty && !keyToggled }
}

enum MediaControl {
    /// apps that tell us their exact player state
    static let scriptable: [String: String] = ["com.apple.Music": "Music", "com.spotify.client": "Spotify"]

    private static func run(_ source: String) -> String? {
        var err: NSDictionary?
        let r = NSAppleScript(source: source)?.executeAndReturnError(&err)
        if let e = err { Log.write("applescript: \(e[NSAppleScript.errorMessage] ?? e)") }
        return r?.stringValue
    }

    /// call off the main thread (it listens for ~0.5 s)
    static func pauseAll(allowKey: Bool) -> PausedMedia {
        var out = PausedMedia()
        let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        for (bid, name) in scriptable where running.contains(bid) {
            let state = DispatchQueue.main.sync {
                run("tell application \"\(name)\" to if player state is playing then\npause\nreturn \"paused\"\nend if\nreturn \"no\"")
            }
            if state == "paused" { out.apps.append(bid) }
        }
        // everything else: only if it is really making sound right now
        if allowKey {
            let loud = AudioSignal.audiblePIDs(excludingBundles: Set(scriptable.keys))
            if !loud.isEmpty {
                Log.write("media: audible \(loud) -> pause key")
                DispatchQueue.main.sync { MediaKeys.playPause() }
                out.keyToggled = true
            }
        }
        if !out.isEmpty { Log.write("media paused: apps=\(out.apps) key=\(out.keyToggled)") }
        return out
    }

    static func resume(_ m: PausedMedia) {
        for bid in m.apps { if let name = scriptable[bid] { _ = run("tell application \"\(name)\" to play") } }
        if m.keyToggled { MediaKeys.playPause() }
    }
}

/// Listens to the real output of other apps (Core Audio process tap, macOS 14.2+).
/// Needs the "System Audio Recording" permission; without it the tap hears silence,
/// so nothing is ever toggled by mistake.
enum AudioSignal {
    static func outputPIDs(excludingBundles: Set<String>) -> [(AudioObjectID, pid_t)] {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyProcessObjectList, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size) == noErr, size > 0 else { return [] }
        var list = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &list) == noErr else { return [] }
        let me = getpid()
        var out: [(AudioObjectID, pid_t)] = []
        for obj in list {
            var a = AudioObjectPropertyAddress(mSelector: kAudioProcessPropertyIsRunningOutput, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
            var running: UInt32 = 0; var s = UInt32(4)
            guard AudioObjectGetPropertyData(obj, &a, 0, nil, &s, &running) == noErr, running == 1 else { continue }
            a.mSelector = kAudioProcessPropertyPID
            var pid: pid_t = 0; s = UInt32(MemoryLayout<pid_t>.size)
            guard AudioObjectGetPropertyData(obj, &a, 0, nil, &s, &pid) == noErr, pid > 0, pid != me else { continue }
            let bid = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier ?? ""
            if excludingBundles.contains(bid) { continue }
            out.append((obj, pid))
        }
        return out
    }

    /// processes whose output is louder than about -50 dB during `seconds`
    static func audiblePIDs(excludingBundles: Set<String>, seconds: Double = 0.6) -> [pid_t] {
        guard #available(macOS 14.2, *) else { return [] }
        var loud: [pid_t] = []
        for (obj, pid) in outputPIDs(excludingBundles: excludingBundles) {
            if peak(of: obj, seconds: seconds) > 0.003 { loud.append(pid) }
        }
        return loud
    }

    @available(macOS 14.2, *)
    static func peak(of process: AudioObjectID, seconds: Double) -> Float {
        let desc = CATapDescription(stereoMixdownOfProcesses: [process])
        desc.uuid = UUID()
        desc.isPrivate = true
        desc.muteBehavior = .unmuted
        var tap = AudioObjectID(kAudioObjectUnknown)
        guard AudioHardwareCreateProcessTap(desc, &tap) == noErr else { return 0 }
        defer { AudioHardwareDestroyProcessTap(tap) }
        let agg: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Azan tap",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceTapListKey: [[kAudioSubTapUIDKey: desc.uuid.uuidString]],
        ]
        var dev = AudioObjectID(kAudioObjectUnknown)
        guard AudioHardwareCreateAggregateDevice(agg as CFDictionary, &dev) == noErr else { return 0 }
        defer { AudioHardwareDestroyAggregateDevice(dev) }
        let box = PeakBox()
        var proc: AudioDeviceIOProcID?
        let q = DispatchQueue(label: "azan.tap")
        guard AudioDeviceCreateIOProcIDWithBlock(&proc, dev, q, { _, input, _, _, _ in
            for b in UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input)) {
                guard let d = b.mData else { continue }
                let n = Int(b.mDataByteSize) / MemoryLayout<Float>.size
                let p = d.assumingMemoryBound(to: Float.self)
                var m: Float = 0
                for i in 0..<n { m = max(m, abs(p[i])) }
                box.add(m)
            }
        }) == noErr, let proc else { return 0 }
        defer { AudioDeviceDestroyIOProcID(dev, proc) }
        guard AudioDeviceStart(dev, proc) == noErr else { return 0 }
        Thread.sleep(forTimeInterval: seconds)
        AudioDeviceStop(dev, proc)
        return q.sync { box.value }
    }

    private final class PeakBox { var value: Float = 0; func add(_ v: Float) { if v.isFinite { value = max(value, v) } } }
}
