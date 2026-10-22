import AppKit
import CryptoKit

/// Checks every file the app needs at start and repairs what it can, without asking.
/// - Bundle files are verified against Resources/manifest.json (SHA-256, written by build.sh).
/// - A healthy copy of them is kept in ~/Library/Application Support/Azan/Spare; if a bundle
///   file is ever missing or damaged, the spare copy is used instead (Res.url).
/// - Login item, widget registration and the data folder are recreated when missing.
enum Res {
    static var spareDir: URL { Paths.dataDir.appendingPathComponent("Spare", isDirectory: true) }
    /// files the self-check found broken in the bundle (relative paths)
    static var broken = Set<String>()

    /// path inside Resources, e.g. "Sounds/makkah.mp3"
    static func url(_ rel: String) -> URL? {
        guard let base = Bundle.main.resourceURL else { return nil }
        let inBundle = base.appendingPathComponent(rel)
        if !broken.contains(rel), FileManager.default.fileExists(atPath: inBundle.path) { return inBundle }
        let spare = spareDir.appendingPathComponent(rel)
        return FileManager.default.fileExists(atPath: spare.path) ? spare : nil
    }
}

struct CheckReport {
    var checked = 0
    var problems: [String] = []
    var repaired: [String] = []
    var date = Date()
    var ok: Bool { problems.isEmpty }
}

enum SelfCheck {
    static func sha256(_ url: URL) -> String? {
        guard let d = try? Data(contentsOf: url) else { return nil }
        return SHA256.hash(data: d).map { String(format: "%02x", $0) }.joined()
    }

    static func manifest(at base: URL) -> [String: String] {
        guard let d = try? Data(contentsOf: base.appendingPathComponent("manifest.json")),
              let m = try? JSONSerialization.jsonObject(with: d) as? [String: String] else { return [:] }
        return m
    }

    /// verify a resources folder against its manifest; returns the broken relative paths
    static func verify(base: URL) -> (checked: Int, broken: [String]) {
        let m = manifest(at: base)
        var bad: [String] = []
        for (rel, hash) in m where sha256(base.appendingPathComponent(rel)) != hash { bad.append(rel) }
        return (m.count, bad.sorted())
    }

    @discardableResult
    static func run(model: AppModel) -> CheckReport {
        var r = CheckReport()
        let fm = FileManager.default

        // 1. data folder
        if !fm.fileExists(atPath: Paths.dataDir.path) {
            try? fm.createDirectory(at: Paths.dataDir, withIntermediateDirectories: true)
            r.repaired.append("مجلد البيانات")
        }

        // 2. bundle files against the manifest, spare copy for repairs
        if let base = Bundle.main.resourceURL {
            let m = manifest(at: base)
            if m.isEmpty { r.problems.append("قائمة الملفات (manifest) ناقصة") }
            let (n, bad) = verify(base: base)
            r.checked = n
            Res.broken = Set(bad)
            for rel in m.keys.sorted() {
                let spare = Res.spareDir.appendingPathComponent(rel)
                let spareOK = sha256(spare) == m[rel]
                if bad.contains(rel) {
                    if spareOK { r.repaired.append(rel) } else { r.problems.append(rel) }
                } else if !spareOK {
                    // keep a healthy spare copy for the future
                    try? fm.createDirectory(at: spare.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try? fm.removeItem(at: spare)
                    try? fm.copyItem(at: base.appendingPathComponent(rel), to: spare)
                }
            }
        }

        // 3. chosen voices must exist, else fall back to one that does
        let available = Voice.all.filter { Res.url("Sounds/\($0.id).mp3") != nil }.map(\.id)
        if let first = available.first {
            if !available.contains(model.settings.voice) { model.settings.voice = first; r.repaired.append("صوت الأذان") }
            if !available.contains(model.settings.fajrVoice) { model.settings.fajrVoice = available.first { $0.contains("fajr") } ?? first; r.repaired.append("صوت الفجر") }
        }

        // 4. start at login
        if model.settings.launchAtLogin {
            let exe = Bundle.main.executableURL?.path ?? ""
            let current = (NSDictionary(contentsOf: LoginItem.plist)?["ProgramArguments"] as? [String])?.first
            if current != exe { LoginItem.set(true); if exe.hasPrefix("/Applications/") { r.repaired.append("التشغيل مع الماك") } }
        }

        // 5. widget registration
        if let appex = Bundle.main.builtInPlugInsURL?.appendingPathComponent("AzanWidget.appex"),
           fm.fileExists(atPath: appex.path), Bundle.main.bundlePath.hasPrefix("/Applications/") {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/pluginkit")
            p.arguments = ["-a", appex.path]
            try? p.run()
        }

        Log.write("selfcheck: \(r.checked) files, problems=\(r.problems), repaired=\(r.repaired)")
        return r
    }

    // MARK: move to /Applications (when started from the DMG or Downloads)

    static var isInApplications: Bool { Bundle.main.bundlePath.hasPrefix("/Applications/") }

    static func offerMoveToApplications() {
        guard !isInApplications, ProcessInfo.processInfo.environment["AZAN_DATA"] == nil else { return }
        let a = NSAlert()
        a.messageText = "نقل أذان لمجلد التطبيقات؟"
        a.informativeText = "عشان يشتغل البرنامج والويدجت والتشغيل مع الماك صح، لازم يكون بمجلد التطبيقات. بنقله هلأ وبرجع أفتحه."
        a.addButton(withTitle: "انقله")
        a.addButton(withTitle: "لاحقاً")
        NSApp.activate(ignoringOtherApps: true)
        guard a.runModal() == .alertFirstButtonReturn else { return }
        let dest = URL(fileURLWithPath: "/Applications/Azan.app")
        let fm = FileManager.default
        do {
            if fm.fileExists(atPath: dest.path) { try fm.trashItem(at: dest, resultingItemURL: nil) }
            try fm.copyItem(at: Bundle.main.bundleURL, to: dest)
            let x = Process()
            x.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
            x.arguments = ["-dr", "com.apple.quarantine", dest.path]
            try? x.run(); x.waitUntilExit()
            let o = Process()
            o.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            o.arguments = ["-n", dest.path]
            try o.run()
            NSApp.terminate(nil)
        } catch {
            let e = NSAlert()
            e.messageText = "ما قدرت أنقله"
            e.informativeText = "اسحب أذان لمجلد التطبيقات بإيدك. (\(error.localizedDescription))"
            e.runModal()
        }
    }
}
