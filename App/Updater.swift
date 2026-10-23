import AppKit
import SwiftUI

/// Daily check for a newer release on GitHub, and one-click install (download DMG → replace the app → reopen).
/// Settings and khatma progress live in Application Support and are never touched.
final class Updater: ObservableObject {
    static let shared = Updater()
    static let repo = "MominAlJafarawi/Azan"

    struct Release { let version: String; let notes: String; let dmg: URL; let page: URL }

    @Published var available: Release?
    @Published var lastCheck: Date? = UserDefaults.standard.object(forKey: "updateLastCheck") as? Date
    @Published var checking = false
    @Published var progress: Double? = nil      // 0...1 while downloading
    @Published var error: String?
    var onAvailable: ((Release) -> Void)?

    static var current: String {
        ProcessInfo.processInfo.environment["AZAN_FAKE_VERSION"]
            ?? (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0")
    }

    /// "1.2.10" > "1.2.9"
    static func isNewer(_ a: String, than b: String) -> Bool {
        let pa = a.split(separator: ".").map { Int($0) ?? 0 }, pb = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(pa.count, pb.count) {
            let x = i < pa.count ? pa[i] : 0, y = i < pb.count ? pb[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    /// once a day (or now when forced)
    func check(force: Bool = false) {
        if !force, let l = lastCheck, Date().timeIntervalSince(l) < 20 * 3600 { return }
        checking = true; error = nil
        var req = URLRequest(url: URL(string: "https://api.github.com/repos/\(Self.repo)/releases/latest")!)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.timeoutInterval = 20
        URLSession.shared.dataTask(with: req) { data, _, err in
            DispatchQueue.main.async {
                self.checking = false
                self.lastCheck = Date()
                UserDefaults.standard.set(self.lastCheck, forKey: "updateLastCheck")
                guard let data, let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let tag = j["tag_name"] as? String else {
                    self.error = err?.localizedDescription ?? "ما قدرت أوصل لـGitHub"
                    Log.write("update check failed: \(self.error ?? "")"); return
                }
                let v = tag.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
                let assets = (j["assets"] as? [[String: Any]]) ?? []
                let dmg = assets.compactMap { $0["browser_download_url"] as? String }.first { $0.hasSuffix("-mac.dmg") }
                Log.write("update check: latest \(v), current \(Self.current)")
                guard Self.isNewer(v, than: Self.current), let d = dmg.flatMap(URL.init(string:)) else { self.available = nil; return }
                let r = Release(version: v, notes: (j["body"] as? String) ?? "", dmg: d,
                                page: URL(string: (j["html_url"] as? String) ?? "https://github.com/\(Self.repo)/releases")!)
                self.available = r
                if UserDefaults.standard.string(forKey: "updateSnoozed") != v || force { self.onAvailable?(r) }
            }
        }.resume()
    }

    func snooze() { if let v = available?.version { UserDefaults.standard.set(v, forKey: "updateSnoozed") } }

    // MARK: install

    func install() {
        guard let r = available, progress == nil else { return }
        progress = 0; error = nil
        let task = URLSession.shared.downloadTask(with: r.dmg) { file, resp, err in
            guard let file, (resp as? HTTPURLResponse)?.statusCode == 200 else {
                DispatchQueue.main.async { self.fail(err?.localizedDescription ?? "فشل التنزيل") }; return
            }
            let dmg = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("Azan-update-\(r.version).dmg")
            try? FileManager.default.removeItem(at: dmg)
            do { try FileManager.default.moveItem(at: file, to: dmg) } catch {
                DispatchQueue.main.async { self.fail("ما قدرت أحفظ الملف") }; return
            }
            self.apply(dmg: dmg, version: r.version)
        }
        obs = task.progress.observe(\.fractionCompleted) { p, _ in DispatchQueue.main.async { self.progress = p.fractionCompleted } }
        task.resume()
    }
    private var obs: NSKeyValueObservation?

    private func fail(_ m: String) { progress = nil; error = m; Log.write("update failed: \(m)") }

    @discardableResult
    private func run(_ path: String, _ args: [String]) -> (Int32, String) {
        let p = Process(); p.executableURL = URL(fileURLWithPath: path); p.arguments = args
        let pipe = Pipe(); p.standardOutput = pipe; p.standardError = pipe
        do { try p.run() } catch { return (-1, error.localizedDescription) }
        let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        p.waitUntilExit()
        return (p.terminationStatus, out)
    }

    /// mount the DMG, copy the new app next to the old one, check it, then swap after we quit
    private func apply(dmg: URL, version: String) {
        let mnt = NSTemporaryDirectory() + "azan-update-mnt"
        try? FileManager.default.createDirectory(atPath: mnt, withIntermediateDirectories: true)
        let (a, aout) = run("/usr/bin/hdiutil", ["attach", "-nobrowse", "-readonly", "-noautoopen", "-mountpoint", mnt, dmg.path])
        guard a == 0 else { DispatchQueue.main.async { self.fail("ما قدرت أفتح ملف التحديث: \(aout.prefix(120))") }; return }
        defer { run("/usr/bin/hdiutil", ["detach", mnt, "-quiet"]) }
        let target = Bundle.main.bundleURL.path
        let staged = target + ".new"
        try? FileManager.default.removeItem(atPath: staged)
        let (c, _) = run("/usr/bin/ditto", ["\(mnt)/Azan.app", staged])
        let newVersion = (NSDictionary(contentsOfFile: staged + "/Contents/Info.plist")?["CFBundleShortVersionString"] as? String) ?? ""
        let (v, vout) = run("/usr/bin/codesign", ["--verify", "--deep", staged])
        guard c == 0, v == 0, newVersion == version else {
            try? FileManager.default.removeItem(atPath: staged)
            DispatchQueue.main.async { self.fail("ملف التحديث مش سليم (\(newVersion) \(vout.prefix(80)))") }; return
        }
        run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", staged])
        if ProcessInfo.processInfo.environment["AZAN_UPDATE_DRYRUN"] != nil {
            Log.write("update dry run ok: \(staged) is \(newVersion)")
            try? FileManager.default.removeItem(atPath: staged)
            DispatchQueue.main.async { self.progress = nil; self.error = "تجربة: التحديث جاهز وسليم (\(newVersion))" }
            return
        }
        // swap after this process exits, then reopen; the old copy goes to a backup until the new one starts
        let pid = getpid()
        let script = """
        while kill -0 \(pid) 2>/dev/null; do sleep 0.3; done
        rm -rf "\(target).old"; mv "\(target)" "\(target).old" && mv "\(staged)" "\(target)" || { mv "\(target).old" "\(target)"; exit 1; }
        /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "\(target)" >/dev/null 2>&1
        open "\(target)" && sleep 8 && rm -rf "\(target).old"
        """
        let p = Process(); p.executableURL = URL(fileURLWithPath: "/bin/sh"); p.arguments = ["-c", script]
        try? p.run()
        Log.write("update: installing \(version), restarting")
        DispatchQueue.main.async { NSApp.terminate(nil) }
    }
}

/// Card shown when a new version is out.
struct UpdateCard: View {
    @ObservedObject var model: AppModel
    @ObservedObject var up = Updater.shared
    var close: () -> Void

    var body: some View {
        let look = model.sky
        PanelCard(look: look) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    Image(systemName: "arrow.down.circle.fill").font(.system(size: 26)).foregroundStyle(look.gold).frame(width: 34)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("نسخة جديدة من أذان").font(AppFont.naskh(24, bold: true))
                        Text("\(up.available?.version ?? "") (عندك \(Updater.current))").font(.system(size: 13)).foregroundStyle(look.secondary)
                    }
                    Spacer()
                    Button(action: close) { Image(systemName: "xmark").font(.system(size: 11, weight: .bold)) }.buttonStyle(.plain).foregroundStyle(look.secondary)
                }
                if let n = up.available?.notes, !n.isEmpty {
                    Text(n.count > 260 ? String(n.prefix(260)) + "…" : n).font(.system(size: 13)).fixedSize(horizontal: false, vertical: true)
                }
                if let p = up.progress {
                    VStack(alignment: .leading, spacing: 4) {
                        GoldBar(value: p, look: look)
                        Text(p < 1 ? "عم ينزّل… \(Fmt.num(Int(p * 100), latin: model.latin))٪" : "عم يثبّت، وبيرجع يفتح لحاله…").font(.system(size: 12)).foregroundStyle(look.secondary)
                    }
                } else {
                    if let e = up.error { Text(e).font(.system(size: 12)).foregroundStyle(.orange) }
                    HStack(spacing: 8) {
                        Button { up.install() } label: {
                            Label("حدّث هلأ", systemImage: "arrow.down.circle").font(.system(size: 13, weight: .semibold))
                                .padding(.horizontal, 12).padding(.vertical, 6)
                                .background(Capsule().fill(look.gold)).foregroundStyle(Color(red: 0.06, green: 0.08, blue: 0.2))
                        }.buttonStyle(.plain)
                        Button { up.snooze(); close() } label: {
                            Text("لاحقاً").font(.system(size: 13, weight: .semibold)).padding(.horizontal, 12).padding(.vertical, 6)
                                .background(Capsule().fill(look.text.opacity(0.1)))
                        }.buttonStyle(.plain)
                        Spacer()
                        if let page = up.available?.page { Link("التفاصيل", destination: page).font(.system(size: 12)) }
                    }
                }
            }
        }
    }
}
