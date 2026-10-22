import SwiftUI
import CoreLocation

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @State private var tab = 0

    var body: some View {
        let look = model.sky
        VStack(spacing: 0) {
            ZStack {
                SkyBackground(look: look).ignoresSafeArea()
                VStack(spacing: 10) {
                    Text("الإعدادات").font(AppFont.naskh(24, bold: true)).foregroundStyle(look.text)
                    GoldTabs(look: look, items: [
                        (0, "الموقع والحساب", "location"),
                        (1, "الأذان", "speaker.wave.2"),
                        (2, "الختمة", "book.closed"),
                        (3, "التذكيرات", "bell"),
                        (4, "عام", "gearshape"),
                    ], selection: $tab)
                }
                .padding(.vertical, 14)
            }
            .frame(height: 110)
            .padding(.top, -28)

            Form {
                switch tab {
                case 0: LocationTab(model: model)
                case 1: AdhanTab(model: model)
                case 2: KhatmaTab(model: model)
                case 3: RemindersTab(model: model)
                default: GeneralTab(model: model)
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .background(look.bottom)
            .tint(look.gold)
        }
        .preferredColorScheme(.dark)
        .environment(\.layoutDirection, .rightToLeft)
        .environment(\.locale, Fmt.locale(latin: model.latin))
        .frame(width: 600, height: 640)
    }
}

private struct LocationTab: View {
    @ObservedObject var model: AppModel
    @State private var query = ""
    @State private var results: [(String, String?, CLLocation)] = []
    @State private var searching = false

    var body: some View {
        Section("الموقع") {
            Toggle("تحديد الموقع تلقائياً من الماك", isOn: $model.settings.autoLocation)
                .onChange(of: model.settings.autoLocation) { _, on in if on { model.location.refresh() } }
            LabeledContent("المدينة الحالية") {
                Text(model.settings.placeName.isEmpty ? "غير محدد" : model.settings.placeName)
            }
            if model.locationDenied && model.settings.autoLocation {
                Text("خدمة الموقع مقفلة. افتحها من إعدادات النظام ← الخصوصية والأمان ← خدمات الموقع، أو اختار مدينتك يدوياً.")
                    .font(.caption).foregroundStyle(.orange)
            }
            if !model.settings.autoLocation || model.locationDenied {
                HStack {
                    TextField("اكتب اسم المدينة (مثلاً Hannover)", text: $query).onSubmit(search)
                    Button("بحث", action: search).disabled(query.isEmpty || searching)
                }
                ForEach(Array(results.enumerated()), id: \.offset) { _, r in
                    Button { pick(r) } label: { Label(r.0, systemImage: "mappin.and.ellipse") }.buttonStyle(.link)
                }
            }
        }
        Section("طريقة الحساب") {
            Toggle("اختيار الطريقة تلقائياً حسب البلد", isOn: $model.settings.autoMethod)
            if model.settings.autoMethod {
                LabeledContent("الطريقة المستعملة", value: model.settings.effectiveMethod.arabic)
            } else {
                Picker("الطريقة", selection: $model.settings.method) {
                    ForEach(CalcMethod.allCases, id: \.self) { Text($0.arabic).tag($0) }
                }
            }
            Picker("مذهب العصر", selection: $model.settings.school) {
                ForEach(AsrSchool.allCases, id: \.self) { Text($0.arabic).tag($0) }
            }
            Picker("خطوط العرض العالية", selection: $model.settings.highLat) {
                ForEach(HighLatRule.allCases, id: \.self) { Text($0.arabic).tag($0) }
            }
            Text("بالبلاد الشمالية (مثل ألمانيا) بالصيف ما بيغيب الشفق تماماً، فهالقاعدة بتحدد وقت الفجر والعشاء هناك. قارن مع مسجدك وعدّل بالدقائق تحت إذا لزم.")
                .font(.caption).foregroundStyle(.secondary)
        }
        Section("تعديل بالدقائق (لتطابق مسجدك)") {
            ForEach(Prayer.allCases, id: \.self) { p in
                Stepper(value: Binding(get: { model.settings.offsets[safe: p.rawValue] ?? 0 },
                                       set: { v in var o = model.settings.offsets; if o.count != 6 { o = [0, 0, 0, 0, 0, 0] }; o[p.rawValue] = v; model.settings.offsets = o }),
                        in: -30...30, step: 1) {
                    HStack {
                        Text(p.arabic)
                        Spacer()
                        let v = Int(model.settings.offsets[safe: p.rawValue] ?? 0)
                        Text(v == 0 ? "بدون" : "\(v > 0 ? "+" : "")\(Fmt.num(v, latin: model.latin)) د").foregroundStyle(.secondary)
                    }
                }
            }
        }
        Section("التاريخ الهجري") {
            Stepper(value: $model.settings.hijriOffset, in: -2...2) {
                HStack {
                    Text("تعديل اليوم")
                    Spacer()
                    Text(Fmt.hijri(model.now, offset: model.settings.hijriOffset, latin: model.latin)).foregroundStyle(.secondary)
                }
            }
            Text("إذا أعلنوا رؤية الهلال بيوم مختلف، عدّل هون.").font(.caption).foregroundStyle(.secondary)
        }
    }

    private func search() {
        searching = true
        model.location.search(query) { r in results = r; searching = false }
    }
    private func pick(_ r: (String, String?, CLLocation)) {
        var s = model.settings
        s.autoLocation = false
        s.latitude = (r.2.coordinate.latitude * 10000).rounded() / 10000
        s.longitude = (r.2.coordinate.longitude * 10000).rounded() / 10000
        s.placeName = r.0.components(separatedBy: "، ").first ?? r.0
        s.countryCode = r.1
        model.settings = s
        results = []
    }
}

private struct AdhanTab: View {
    @ObservedObject var model: AppModel
    var body: some View {
        Section("الصوت") {
            voicePicker("صوت الأذان", $model.settings.voice)
            voicePicker("صوت أذان الفجر", $model.settings.fajrVoice)
            HStack {
                Image(systemName: "speaker.fill")
                Slider(value: $model.settings.volume, in: 0.1...1)
                Image(systemName: "speaker.wave.3.fill")
            }
        }
        Section("لكل صلاة") {
            ForEach(Prayer.allCases, id: \.self) { p in
                Picker(p.arabic, selection: Binding(get: { model.settings.mode(p) }, set: { model.settings.setMode($0, for: p) })) {
                    ForEach(AlertMode.allCases, id: \.self) { Text($0.arabic).tag($0) }
                }
            }
        }
        Section("التنبيه قبل الأذان") {
            Picker("قبلها بـ", selection: $model.settings.preReminder) {
                Text("بدون").tag(0)
                ForEach([5, 10, 15, 20, 30], id: \.self) { Text("\(Fmt.num($0, latin: model.latin)) دقائق").tag($0) }
            }
        }
        Section("الأذان الذكي") {
            Toggle("إيقاف الموسيقى والفيديو وقت الأذان ثم إرجاعها", isOn: $model.settings.smartPause)
            if model.settings.smartPause {
                Text("بيوقّف بس اللي عم يطلع منه صوت فعلاً. Music وSpotify بيسألهم مباشرة، والمتصفح (يوتيوب) بيسمع صوته نص ثانية قبل ما يوقّفه، فالفيديو الموقّف ما بيشتغل أبداً. أول مرة بيطلب إذن \"تسجيل صوت النظام\" وإذن التحكم بـMusic/Spotify، وما بيسجّل ولا بيحفظ أي صوت.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if model.settings.smartPause && !MediaKeys.trusted {
                HStack {
                    Text("بحتاج إذن \"تسهيلات الاستخدام\" مرة وحدة عشان أقدر أوقف الموسيقى.").font(.caption)
                    Spacer()
                    Button("إعطاء الإذن") { MediaKeys.askForPermission() }
                }
            }
            Toggle("وقت الاجتماعات (المايك شغّال): تنبيه صامت بدل الأذان", isOn: $model.settings.meetingSilent)
        }
        Section("التنبيه الصامت بالكلام") {
            Toggle("بدل الأذان: صوت بيقول \"حان الآن موعد أذان …\"", isOn: $model.settings.speakOn)
            if model.settings.speakOn {
                Toggle("ابدأ بـ\"الله أكبر\" بصوت الشيخ المختار", isOn: $model.settings.speakTakbir)
                Picker("عدد مرات الجملة", selection: $model.settings.speakRepeats) {
                    ForEach(1...3, id: \.self) { Text(Fmt.num($0, latin: model.latin)).tag($0) }
                }
                HStack {
                    Text("علو الصوت")
                    Slider(value: $model.settings.speakVolume, in: 0.1...1)
                }
                Toggle("حتى وقت الاجتماعات", isOn: $model.settings.speakInMeeting)
                if model.settings.speakInMeeting {
                    Text("إذا الصوت طالع من سماعات الماك مش من سماعة الأذن، ممكن اللي معك بالاجتماع يسمعوه.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                HStack {
                    Spacer()
                    Button {
                        model.announce(model.nextPrayer?.0 ?? .fajr)
                    } label: { Label("اسمع التنبيه", systemImage: "speaker.wave.1") }
                }
            }
            Text("بيشتغل للصلوات اللي حاططها \"تنبيه صامت\"، ووقت الاجتماعات.").font(.caption).foregroundStyle(.secondary)
            Label("الصوت: ماجد (مسجّل داخل البرنامج)", systemImage: "person.wave.2").font(.caption).foregroundStyle(.secondary)
        }
        Section("تجربة") {
            HStack {
                Text("جرّب الأذان كامل متل ما بيطلع وقت الصلاة (الكرت والصوت وإيقاف الموسيقى)")
                Spacer()
                Button { model.onTestAdhan?() } label: { Label("تجربة الأذان", systemImage: "play.fill") }
                    .buttonStyle(.borderedProminent)
            }
        }
    }

    private func voicePicker(_ title: String, _ sel: Binding<String>) -> some View {
        HStack {
            Picker(title, selection: sel) {
                ForEach(Voice.all) { Text($0.name).tag($0.id) }
            }
            Button { model.preview(sel.wrappedValue) } label: { Image(systemName: "play.circle") }
                .buttonStyle(.plain).help("استماع / إيقاف")
        }
    }
}

private struct KhatmaTab: View {
    @ObservedObject var model: AppModel
    @State private var page = 0
    var body: some View {
        let k = model.settings.khatma
        Section("خطة الختمة") {
            Toggle("تفعيل ورد القرآن", isOn: $model.settings.khatmaOn)
            Picker("أختم خلال", selection: $model.settings.khatmaDays) {
                ForEach([7, 10, 15, 20, 30, 40, 60, 90, 120, 365], id: \.self) { Text("\(Fmt.num($0, latin: model.latin)) يوم").tag($0) }
            }
            LabeledContent("ورد اليوم تقريباً", value: "\(Fmt.num(Int(k.perDay.rounded(.up)), latin: model.latin)) صفحة، يعني \(Fmt.num(k.chunk, latin: model.latin)) بعد كل صلاة")
            LabeledContent("بدأت", value: Fmt.gregorian(k.start, latin: model.latin))
            LabeledContent("وصلت لصفحة", value: "\(Fmt.num(k.lastRead, latin: model.latin)) (سورة \(Quran.surah(onPage: max(1, k.lastRead))))")
            if model.settings.khatmaCount > 0 {
                LabeledContent("ختمات مكتملة", value: Fmt.num(model.settings.khatmaCount, latin: model.latin))
            }
            Toggle("ذكّرني بوردي بعد كل صلاة", isOn: $model.settings.khatmaAfterPrayer)
        }
        Section("تعديل يدوي") {
            Stepper(value: $page, in: 0...Quran.pages) {
                Text("آخر صفحة قرأتها: \(Fmt.num(page, latin: model.latin))")
            }
            HStack {
                Button("حفظ الصفحة") { var s = model.settings; s.khatmaRead = page; model.settings = s }
                Spacer()
                Button("ابدأ ختمة جديدة من اليوم") { model.newKhatma(days: model.settings.khatmaDays) }
            }
        }
        .onAppear { page = model.settings.khatmaRead }
    }
}

private struct RemindersTab: View {
    @ObservedObject var model: AppModel
    var body: some View {
        Section("الأذكار") {
            Toggle("أذكار الصباح (بعد الشروق)", isOn: $model.settings.adhkarMorning)
            Toggle("أذكار المساء (بعد العصر)", isOn: $model.settings.adhkarEvening)
            Toggle("أذكار بعد الصلاة (بعد الأذان بـ٢٠ دقيقة)", isOn: $model.settings.adhkarAfterPrayer)
        }
        Section("يوم الجمعة") {
            Toggle("تذكير بسورة الكهف (الساعة ١٠ الصبح) وبالخطبة", isOn: $model.settings.jumuah)
            Picker("الخطبة: ذكّرني قبل الظهر بـ", selection: $model.settings.khutbahBefore) {
                ForEach([15, 30, 45, 60], id: \.self) { Text("\(Fmt.num($0, latin: model.latin)) دقيقة").tag($0) }
            }
        }
        Section("رمضان") {
            Picker("السحور: ذكّرني قبل الفجر بـ", selection: $model.settings.suhoorBefore) {
                ForEach([30, 45, 60, 90], id: \.self) { Text("\(Fmt.num($0, latin: model.latin)) دقيقة").tag($0) }
            }
            Text("وضع رمضان بيشتغل لحاله لما يبلش الشهر حسب التاريخ الهجري.").font(.caption).foregroundStyle(.secondary)
        }
    }
}

private struct GeneralTab: View {
    @ObservedObject var model: AppModel
    var body: some View {
        Section("العرض") {
            Picker("الأرقام", selection: $model.settings.latinDigits) {
                Text("١٢٣ عربية").tag(false)
                Text("123 لاتينية").tag(true)
            }
            Picker("الساعة", selection: $model.settings.use24h) {
                Text("٢٤ ساعة").tag(true)
                Text("١٢ ساعة").tag(false)
            }
        }
        Section("ويدجت سطح المكتب المتحرك") {
            Toggle("إظهار الويدجت العائم على سطح المكتب", isOn: $model.settings.deskOn)
            Picker("الحجم", selection: $model.settings.deskSize) {
                ForEach(DeskSize.allCases, id: \.self) { Text($0.arabic).tag($0) }
            }
            HStack {
                Text("حجم الويدجت")
                Slider(value: $model.settings.deskScale, in: 0.6...2, step: 0.05)
                Text("\(Fmt.num(Int((model.settings.deskScale * 100).rounded()), latin: model.latin))٪").monospacedDigit().frame(width: 48)
            }
            HStack {
                Text("حجم نافذة البرنامج")
                Slider(value: $model.settings.panelScale, in: 0.8...1.5, step: 0.05)
                Text("\(Fmt.num(Int((model.settings.panelScale * 100).rounded()), latin: model.latin))٪").monospacedDigit().frame(width: 48)
            }
            Toggle("فوق كل النوافذ (بدل ما يكون على سطح المكتب)", isOn: $model.settings.deskOnTop)
            Text("اسحبه بالماوس لأي مكان، واسحب الزاوية التحتانية اليمين لتكبّره أو تصغّره. وكبسة يمين عليه فيها خيارات الحجم والساعة.").font(.caption).foregroundStyle(.secondary)
        }
        Section("فحص الملفات") {
            let c = model.check
            Label(c.ok ? "كل الملفات سليمة (\(Fmt.num(c.checked, latin: model.latin)) ملف)" : "في ملفات ناقصة: \(c.problems.joined(separator: "، "))",
                  systemImage: c.ok ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(c.ok ? model.sky.gold : .orange)
            if !c.repaired.isEmpty {
                Text("صلّحت لحالي: \(c.repaired.joined(separator: "، "))").font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Text("آخر فحص: \(Fmt.time(c.date, latin: model.latin, use24h: model.settings.use24h))").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button { model.check = SelfCheck.run(model: model) } label: { Label("افحص وصلّح الآن", systemImage: "stethoscope") }
            }
        }
        Section("التشغيل") {
            Toggle("يشتغل لحاله لما يفتح الماك", isOn: $model.settings.launchAtLogin)
        }
        Section("حول") {
            LabeledContent("الإصدار", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
            Text("أصوات الأذان من مستودع Kiwifu/adhan-mp3 للاستعمال الشخصي. الأذكار من حصن المسلم. الخط Amiri برخصة OFL.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}
