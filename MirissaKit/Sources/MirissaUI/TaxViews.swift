import SwiftUI
import MirissaCore

/// Finans & Vergiler → Vergiler: ticari kârdan tahmini vergiye kalem kalem.
/// Her rakam tahmindir; beyanname değildir. Girilmemiş bilgi "girilmedi" yazar.
struct VergiKarti: View {
    @Environment(AppStore.self) private var store
    var month: MonthKey
    @State private var ayarAcik = false

    var body: some View {
        if let v = store.engine.vergiKarsiligi(month: month) {
            Card {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Tahmini vergi karşılığı · \(String(v.yil))", systemImage: "building.columns")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Palette.ink)
                    Text(kaynakYazisi(v))
                        .font(.caption).foregroundStyle(Palette.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                    Divider().overlay(Palette.separator)
                    LabeledRow("Ticari kâr (vergi öncesi, \(Dates.displayMonth(min(month, Dates.currentMonth()))) sonuna kadar)",
                               v.yilBasindanKar.tl)
                    LabeledRow("KKEG işaretli giderler (+)", v.kkegGiderler.tl, tone: Palette.inkSoft)
                    LabeledRow("Diğer KKEG (+)", v.kkegEk?.tl ?? "girilmedi", tone: v.kkegEk == nil ? Palette.inkFaint : Palette.inkSoft)
                    LabeledRow("İstisna / indirimler (−)", v.istisnaIndirim?.tl ?? "girilmedi",
                               tone: v.istisnaIndirim == nil ? Palette.inkFaint : Palette.inkSoft)
                    LabeledRow("Geçmiş yıl zararları (−)", v.gecmisYilZarari?.tl ?? "girilmedi",
                               tone: v.gecmisYilZarari == nil ? Palette.inkFaint : Palette.inkSoft)
                    LabeledRow("Tahmini vergi matrahı", v.matrah.tl, strong: true)
                    Divider().overlay(Palette.separator)
                    LabeledRow(vergiAdi(v), v.yilBasindanVergi.tl, strong: true)
                    if v.asgariUygulandi {
                        Text("Yurt içi asgari kurumlar vergisi uygulandı: hesaplanan vergi, indirim ve istisnalardan önceki kazancın %10'undan az olamaz.")
                            .font(.caption2).foregroundStyle(Palette.uyari)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    LabeledRow("Pazaryeri tevkifatları (e-ticaret stopajı)", v.yilBasindanStopaj.tl, tone: Palette.inkSoft)
                    LabeledRow("Önceki çeyreklerin tahmini geçici vergileri", v.oncekiGeciciVergiler.tl, tone: Palette.inkSoft)
                    LabeledRow("Mahsup edilecek vergiler", v.mahsupEdilecek.tl, tone: Palette.inkSoft)
                    if v.ceyrekGeciciVergi > 0 {
                        LabeledRow("\(v.ceyrek). çeyrek tahmini geçici vergi (son gün \(Dates.displayDateShort(v.ceyrekSonOdeme)))",
                                   v.ceyrekGeciciVergi.tl, tone: Palette.uyari)
                    } else if v.ceyrek == 4 && v.yil < 2025 {
                        Text("4. çeyrek için geçici vergi yok; yıllık beyanda ödenir (son gün \(Dates.displayDateShort(v.yillikSonOdeme))).")
                            .font(.caption).foregroundStyle(Palette.inkFaint)
                    }
                    LabeledRow("Tahmini kalan vergi borcu", v.kalanVergiBorcu.tl, tone: Palette.uyari, strong: true)
                    if v.mahsupFazlasi > 0 {
                        LabeledRow("Mahsup edilemeyen fazla (iade/mahsup talebi)", v.mahsupFazlasi.tl, tone: Palette.inkSoft)
                    }
                    Divider().overlay(Palette.separator)
                    LabeledRow("Vergi sonrası tahmini net kâr", v.vergiSonrasiNetKar.tl,
                               tone: v.vergiSonrasiNetKar < 0 ? Palette.zarar : Palette.kar, strong: true)
                    if !v.eksikler.isEmpty {
                        Text("Tahmini: \(v.eksikler.joined(separator: ", ")) girilmedi, bu yüzden hesaba katılmadı. Gerçek vergi farklı olabilir.")
                            .font(.caption2).foregroundStyle(Palette.uyari)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if v.kuralTahmini {
                        Text("\(String(v.yil)) yılının tarifesi uygulamada yok; en yakın yılın tarifesi kullanıldı.")
                            .font(.caption2).foregroundStyle(Palette.uyari)
                    }
                    Text("Tahmindir, beyanname değildir. Kesin tutarı muhasebecin hesaplar.")
                        .font(.caption2).foregroundStyle(Palette.inkFaint)
                        .fixedSize(horizontal: false, vertical: true)
                    Button(ayarAcik ? "Kapat" : "KKEG, istisna, geçmiş yıl zararı gir") {
                        withAnimation(.snappy(duration: 0.2)) { ayarAcik.toggle() }
                    }
                    .font(.footnote.weight(.semibold)).buttonStyle(.plain).foregroundStyle(Palette.accent)
                    if ayarAcik { VergiTutarlariGirisi(yil: v.yil).id(v.yil) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            Card(background: Palette.inset) {
                Text("Vergi tahmini için Ayarlar → Vergi'den şirket türünü seç. Seçilmeden hiçbir vergi rakamı gösterilmez.")
                    .font(.footnote).foregroundStyle(Palette.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func vergiAdi(_ v: VergiKarsiligi) -> String {
        switch v.kaynak {
        case .kanun(sirket: true): return "Tahmini kurumlar vergisi (%\(Money.formatPercent(v.oranPct).dropFirst()))"
        case .kanun(sirket: false): return "Tahmini gelir vergisi (tarife)"
        case .elleOran: return "Tahmini vergi (girdiğin oranla)"
        }
    }

    private func kaynakYazisi(_ v: VergiKarsiligi) -> String {
        switch v.kaynak {
        case .kanun(sirket: true):
            return "Limited/anonim: kurumlar vergisi %25 ve yurt içi asgari kurumlar vergisi (%10; kuruluşun ilk 3 yılında yok) kuralıyla. Geçici vergi aynı hesapla, 4 çeyrekte (2025'ten itibaren 4. çeyrek dahil)."
        case .kanun(sirket: false):
            return "Şahıs şirketi: yıllık gelir vergisi tarifesiyle (2026: %15–%40); geçici vergi %15, 4 çeyrekte. Yıllık vergi Mart ve Temmuz'da iki taksit. Başka gelirlerin (ücret, kira) varsa gerçek vergi farklıdır."
        case let .elleOran(o):
            return "Senin girdiğin %\(Money.formatPercent(o).dropFirst()) oranla (kanundaki kural yerine)."
        }
    }
}

/// Yıllık KKEG (ek), istisna/indirim ve geçmiş yıl zararı girişi. Boş = girilmedi.
struct VergiTutarlariGirisi: View {
    @Environment(AppStore.self) private var store
    var yil: Int
    @State private var kkeg: Kurus?
    @State private var istisna: Kurus?
    @State private var zarar: Kurus?
    @State private var yuklendi = false

    var body: some View {
        VStack(spacing: 8) {
            GirilmediTutarAlani("Diğer KKEG (\(String(yil)))", deger: $kkeg)
            GirilmediTutarAlani("İstisna / indirimler", deger: $istisna)
            GirilmediTutarAlani("Geçmiş yıl zararları (son 5 yıl)", deger: $zarar)
            Button("Kaydet") {
                store.vergiTutarlari(yil: yil, kkegEk: kkeg, gecmisZarar: zarar, istisna: istisna)
            }
            .font(.subheadline.weight(.semibold))
            .frame(maxWidth: .infinity, alignment: .trailing)
            Text("Yok ise 0 yaz. Boş bırakılan \"girilmedi\" görünür ve sonuç tahmini kalır. "
                 + "Gideri KKEG olan kayıtları gider formunda \"KKEG\" diye işaretlersen burada ayrıca yazma.")
                .font(.caption2).foregroundStyle(Palette.inkFaint)
                .fixedSize(horizontal: false, vertical: true)
        }
        .onAppear {
            guard !yuklendi else { return }
            yuklendi = true
            let ek = store.state.settings.ek, k = "\(yil)"
            kkeg = ek.kkegEk?[k]; istisna = ek.istisnaIndirim?[k]; zarar = ek.gecmisYilZarari?[k]
        }
    }
}

/// Ayarlar → Vergi
struct VergiAyari: View {
    @Environment(AppStore.self) private var store
    @State private var oran: Double?
    @State private var yuklendi = false

    var body: some View {
        Section {
            Picker("Şirket türü", selection: Binding(
                get: { store.state.settings.ek.vergiTuru ?? "" },
                set: { yeni in store.ekAyarla { $0.vergiTuru = yeni.isEmpty ? nil : yeni } })) {
                Text("Seçilmedi").tag("")
                Text("Şahıs şirketi").tag("sahis")
                Text("Limited / anonim").tag("sirket")
            }
            if store.state.settings.ek.vergiTuru == "sirket" {
                Picker("Şirketin kuruluş yılı", selection: Binding(
                    get: { store.state.settings.ek.kurulusYili ?? 0 },
                    set: { yeni in store.ekAyarla { $0.kurulusYili = yeni == 0 ? nil : yeni } })) {
                    Text("Girilmedi").tag(0)
                    ForEach((1990...Dates.year(of: Dates.currentMonth())).reversed(), id: \.self) { y in
                        Text(String(y)).tag(y)
                    }
                }
            }
            OptionalQtyField("Muhasebecinin verdiği oran (isteğe bağlı)", suffix: "%", value: $oran)
                .onChange(of: oran) { _, yeni in
                    store.ekAyarla { $0.vergiOrani = yeni.flatMap { $0 > 0 ? min($0, 60) : nil } }
                }
        } header: {
            Text("Tahmini vergi karşılığı")
        } footer: {
            Text("Şirket türünü seçmen yeterli: limited/anonimde kurumlar vergisi (%25, asgari %10), şahısta gelir vergisi tarifesi kullanılır. "
                 + "Muhasebecin sabit bir oran söylediyse yaz; o zaman kanundaki kural yerine o oran kullanılır. "
                 + "Tür seçilmezse vergi tahmini yapılmaz.")
        }
        .onAppear {
            guard !yuklendi else { return }
            yuklendi = true
            oran = store.state.settings.ek.vergiOrani
        }
    }
}

/// Boş bırakılabilen tutar: boşken "girilmedi" yazar, 0 uydurmaz
struct GirilmediTutarAlani: View {
    var baslik: String
    @Binding var deger: Kurus?
    @State private var metin = ""

    init(_ baslik: String, deger: Binding<Kurus?>) {
        self.baslik = baslik
        self._deger = deger
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(baslik).font(.subheadline).foregroundStyle(Palette.ink)
                if deger == nil { Text("girilmedi").font(.caption).foregroundStyle(Palette.inkFaint) }
            }
            Spacer(minLength: 12)
            TextField("", text: $metin)
                .multilineTextAlignment(.trailing)
                .numericKeyboard()
                .frame(maxWidth: 130)
            Text("TL").foregroundStyle(Palette.inkFaint).font(.subheadline)
        }
        .onAppear { metin = deger.map { NumberInput.display($0) } ?? "" }
        .onChange(of: metin) { _, yeni in
            deger = yeni.trimmingCharacters(in: .whitespaces).isEmpty ? nil : (NumberInput.kurus(yeni) ?? 0)
        }
    }
}
