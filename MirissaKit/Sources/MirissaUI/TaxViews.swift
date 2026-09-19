import SwiftUI
import MirissaCore

/// Finans & Vergiler → Vergiler: ticari kârdan vergi sonrası net kâra zincir halinde.
/// Her satırın formülü ve kaynağı altında yazar. Her rakam tahmindir; beyanname değildir.
struct VergiKarti: View {
    @Environment(AppStore.self) private var store
    var month: MonthKey
    @State private var ayarAcik = false

    var body: some View {
        if let v = store.engine.vergiKarsiligi(month: month) {
            VStack(spacing: Metrics.gap) {
                Card {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("Tahmini vergi · \(String(v.yil)) (\(Dates.displayMonth(min(month, Dates.currentMonth()))) sonuna kadar)",
                              systemImage: "building.columns")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Palette.ink)
                        zincir(v)
                        if !v.eksikler.isEmpty {
                            Text("Tahmini: \(v.eksikler.joined(separator: ", ")) girilmedi ya da doğrulanmadı; hesaba katılmadı. Gerçek vergi farklı olabilir.")
                                .font(.caption2).foregroundStyle(Palette.uyari)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if v.kuralTahmini {
                            Text("\(String(v.yil)) yılının tarifesi uygulamada yok; en yakın yılın tarifesi kullanıldı.")
                                .font(.caption2).foregroundStyle(Palette.uyari)
                        }
                        Text("Tahmindir, beyanname değildir. Kesin tutarı muhasebecin hesaplar.")
                            .font(.caption2).foregroundStyle(Palette.inkFaint)
                        Button(ayarAcik ? "Kapat" : "KKEG, istisna, geçmiş yıl zararı gir") {
                            withAnimation(.snappy(duration: 0.2)) { ayarAcik.toggle() }
                        }
                        .font(.footnote.weight(.semibold)).buttonStyle(.plain).foregroundStyle(Palette.accent)
                        if ayarAcik { VergiTutarlariGirisi(yil: v.yil).id(v.yil) }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                GeciciVergiKarti(v: v)
            }
        } else {
            Card(background: Palette.inset) {
                Text("Vergi tahmini için Ayarlar → Vergi'den şirket türünü seç. Seçilmeden hiçbir vergi rakamı gösterilmez.")
                    .font(.footnote).foregroundStyle(Palette.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private func zincir(_ v: VergiKarsiligi) -> some View {
        let kkeg = v.kkegGiderler + (v.kkegEk ?? 0)
        let sirket: Bool = { if case .kanun(sirket: true) = v.kaynak { return true }; return false }()
        let vergiAdi = sirket ? "kurumlar vergisi" : "vergi"
        adim("Ticari kâr (vergi öncesi)", v.yilBasindanKar.tl,
             formul: "Gerçek ciro − bütün giderler (yılbaşından)", kaynak: "Uygulamanın kâr hesabı")
        adim("Normal vergi matrahı", v.matrah.tl,
             formul: "max(ticari kâr + KKEG \(kkeg.tl) − istisna/indirim \(v.istisnaIndirim?.tl ?? "girilmedi") − geçmiş yıl zararı \(v.gecmisYilZarari?.tl ?? "girilmedi"), 0)",
             kaynak: "KVK md. 6, 8–11 (KKEG), 9 (zarar mahsubu), 10 (indirimler)")
        adim("Normal \(vergiAdi)", v.normalVergi.tl, formul: normalFormul(v), kaynak: normalKaynak(v))
        if let am = v.asgariMatrah, let av = v.asgariVergi {
            adim("Asgari vergi matrahı", am.tl,
                 formul: v.asgariZararIndirildi
                    ? "max(ticari kâr + KKEG − geçmiş yıl zararı, 0) — geçmiş yıl zararı MUHASEBECİ UYGULAMASI olarak düşüldü (Danıştay 3. D. E.2024/5700 K.2025/4831; kesinleşmesi doğrulanmadı)"
                    : "max(ticari kâr + KKEG, 0) — istisna/indirim ve geçmiş yıl zararı düşülmez",
                 kaynak: "KVK md. 32/C-6 ve 32/C-2; GİB Yurt İçi Asgari KV Rehberi (Nisan 2026)")
            adim("Asgari kurumlar vergisi", av.tl, formul: "asgari matrah × %10", kaynak: "KVK md. 32/C-1")
        } else {
            adim("Asgari kurumlar vergisi", "uygulanmıyor", formul: v.asgariYokNedeni ?? "", kaynak: "KVK md. 32/C")
        }
        adim("Uygulanacak vergi", v.yilBasindanVergi.tl,
             formul: v.asgariMatrah == nil ? "normal vergi" : "max(normal, asgari)"
                + (v.asgariUygulandi ? " → asgari uygulandı" : ""),
             kaynak: "KVK md. 32/C-1", vurgu: true)
        adim("%5 uyum indirimi", v.uyumDurumu == .evet ? "−" + v.kullanilanUyumIndirimi.tl
                : (v.uyumDurumu == .hayir ? "yok (şartlar sağlanmıyor)" : "hesaba katılmadı"),
             formul: v.uyumDurumu == .evet
                ? "min(uygulanacak vergi × %5, üst sınır\(v.uyumUstSiniriBilinmiyor ? " — \(String(v.yil)) sınırı yayımlanmadı, uygulanmadı" : "")); tevkifat ve ödenmiş geçici vergiden sonra kalan vergiden düşülür"
                    + (v.uyumIndirimiDevreden > 0 ? ". Düşülemeyen \(v.uyumIndirimiDevreden.tl) bir yıl içinde diğer vergilere mahsup edilebilir (iade edilmez)" : "")
                : (v.uyumDurumu == .hayir ? "Ayarlar → Vergi: Hayır" : "Ayarlar → Vergi: Bilmiyorum — %5 uyum indirimi hesaba katılmadı"),
             kaynak: "GVK mük. md. 121; üst sınır GV Genel Tebliği Seri 332 (2025 kazancı: 12.000.000 TL)")
        adim("E-ticaret tevkifat mahsubu", "−" + v.yilBasindanStopaj.tl,
             formul: "pazaryerlerinin kestiği %1 stopaj (KDV hariç satış × %1)", kaynak: "GVK 94/1-19, KVK 15/1-h ve 34; CBK 9284; GVGT 330")
        adim("Ödenmiş geçici vergi mahsubu", "−" + v.odenmisGeciciVergiler.tl,
             formul: "yalnız ödemesi girilmiş geçici vergiler (\(v.geciciDonemler.filter { $0.odeme != nil }.count) dönem); ödenmemiş olan mahsup edilmez",
             kaynak: "KVK md. 34/4, GVK mük. md. 120")
        adim("Kalan tahmini \(vergiAdi)", v.kalanVergiBorcu.tl,
             formul: "max(uygulanacak − tevkifat − ödenmiş geçici vergi, 0) − kullanılan uyum indirimi",
             kaynak: "Son gün \(Dates.displayDateShort(v.yillikSonOdeme))", vurgu: true)
        if v.mahsupFazlasi > 0 {
            adim("Mahsup edilemeyen fazla", v.mahsupFazlasi.tl,
                 formul: "tevkifat + ödenmiş geçici vergi − ödenecek vergi", kaynak: "GVK mük. 120, GVGT 252 (iade/mahsup talebi)")
        }
        adim("Vergi sonrası tahmini net kâr", v.vergiSonrasiNetKar.tl,
             formul: "ticari kâr − (uygulanacak vergi − kullanılan uyum indirimi); tevkifat ve geçici vergi verginin peşin ödemesidir, ayrıca düşülmez",
             kaynak: "Tahmin", vurgu: true)
    }

    private func normalFormul(_ v: VergiKarsiligi) -> String {
        switch v.kaynak {
        case .kanun(sirket: true): return "normal matrah × %\(Money.formatPercent(v.oranPct).dropFirst())"
        case .kanun(sirket: false): return "normal matrah üzerine \(String(v.yil)) gelir vergisi tarifesi (%15–%40)"
        case let .elleOran(o): return "normal matrah × %\(Money.formatPercent(o).dropFirst()) (senin girdiğin oran)"
        }
    }

    private func normalKaynak(_ v: VergiKarsiligi) -> String {
        switch v.kaynak {
        case .kanun(sirket: true): return "KVK md. 32/1 (7456 sayılı Kanun)"
        case .kanun(sirket: false): return "GVK md. 103; GV Genel Tebliği Seri 332"
        case .elleOran: return "Muhasebecinin verdiği oran"
        }
    }

    private func adim(_ ad: String, _ deger: String, formul: String, kaynak: String, vurgu: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Divider().overlay(Palette.separator)
            LabeledRow(ad, deger, tone: vurgu ? Palette.ink : Palette.inkSoft, strong: vurgu)
            Text(formul).font(.caption2).foregroundStyle(Palette.inkFaint)
                .fixedSize(horizontal: false, vertical: true)
            Text("Kaynak: \(kaynak)").font(.caption2).foregroundStyle(Palette.inkFaint)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Geçici vergi dönemleri: hesaplanan, ödenen, kalan, vade. Ödeme kaydı yoksa ödenmemiş sayılır.
struct GeciciVergiKarti: View {
    @Environment(AppStore.self) private var store
    var v: VergiKarsiligi
    @State private var duzenlenen: GeciciVergiDonemi?
    @State private var tutar: Kurus = 0
    @State private var tarih: DateKey = Dates.today()
    @State private var yillikDuzenle = false

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                Text("GEÇİCİ VERGİ · \(String(v.yil))")
                    .font(.caption.weight(.semibold)).tracking(0.6).foregroundStyle(Palette.inkFaint)
                if v.geciciDonemler.isEmpty {
                    Text("Bu yıl için henüz geçici vergi dönemi yok.").font(.caption).foregroundStyle(Palette.inkFaint)
                }
                ForEach(v.geciciDonemler) { d in
                    VStack(alignment: .leading, spacing: 4) {
                        Divider().overlay(Palette.separator)
                        Text("\(d.ceyrek). dönem\(d.bitti ? "" : " (devam ediyor, tahmini)") · son gün \(Dates.displayDateShort(d.vade))")
                            .font(.footnote.weight(.semibold)).foregroundStyle(Palette.ink)
                        LabeledRow("Hesaplanan (tahakkuk)", d.tahakkuk.tl, tone: Palette.inkSoft)
                        LabeledRow("Ödenen", d.odeme.map { "\($0.tutar.tl) · \(Dates.displayDateShort($0.tarih))" } ?? "ödeme girilmedi",
                                   tone: d.odeme == nil ? Palette.inkFaint : Palette.inkSoft)
                        LabeledRow("Kalan", d.kalan.tl,
                                   tone: d.kalan > 0 && d.vade < Dates.today() ? Palette.zarar : Palette.inkSoft, strong: true)
                        if duzenlenen?.id == d.id {
                            MoneyField("Ödenen tutar", value: $tutar)
                            DateRow(label: "Ödeme tarihi", dateKey: $tarih)
                            HStack {
                                Button("Kaydet") {
                                    store.geciciVergiOdemesi(yil: d.yil, ceyrek: d.ceyrek,
                                                             tutar > 0 ? VergiOdemesi(tutar: tutar, tarih: tarih) : nil)
                                    duzenlenen = nil
                                }
                                .font(.footnote.weight(.semibold))
                                if d.odeme != nil {
                                    Button("Ödemeyi sil", role: .destructive) {
                                        store.geciciVergiOdemesi(yil: d.yil, ceyrek: d.ceyrek, nil)
                                        duzenlenen = nil
                                    }
                                    .font(.footnote)
                                }
                                Spacer()
                                Button("Vazgeç") { duzenlenen = nil }.font(.footnote)
                            }
                        } else {
                            Button(d.odeme == nil ? "Ödemeyi gir" : "Ödemeyi değiştir") {
                                tutar = d.odeme?.tutar ?? d.tahakkuk
                                tarih = d.odeme?.tarih ?? min(Dates.today(), d.vade)
                                duzenlenen = d
                            }
                            .font(.footnote.weight(.semibold)).buttonStyle(.plain).foregroundStyle(Palette.accent)
                        }
                    }
                }
                Divider().overlay(Palette.separator)
                Text("Yıllık beyan · son gün \(Dates.displayDateShort(v.yillikSonOdeme))")
                    .font(.footnote.weight(.semibold)).foregroundStyle(Palette.ink)
                LabeledRow("Tahmini kalan vergi", v.kalanVergiBorcu.tl, tone: Palette.inkSoft)
                LabeledRow("Ödenen", v.yillikOdeme.map { "\($0.tutar.tl) · \(Dates.displayDateShort($0.tarih))" } ?? "ödeme girilmedi",
                           tone: v.yillikOdeme == nil ? Palette.inkFaint : Palette.inkSoft)
                if yillikDuzenle {
                    MoneyField("Ödenen tutar", value: $tutar)
                    DateRow(label: "Ödeme tarihi", dateKey: $tarih)
                    HStack {
                        Button("Kaydet") {
                            store.yillikVergiOdemesi(yil: v.yil, tutar > 0 ? VergiOdemesi(tutar: tutar, tarih: tarih) : nil)
                            yillikDuzenle = false
                        }
                        .font(.footnote.weight(.semibold))
                        if v.yillikOdeme != nil {
                            Button("Ödemeyi sil", role: .destructive) {
                                store.yillikVergiOdemesi(yil: v.yil, nil); yillikDuzenle = false
                            }
                            .font(.footnote)
                        }
                        Spacer()
                        Button("Vazgeç") { yillikDuzenle = false }.font(.footnote)
                    }
                } else if v.yil < Dates.year(of: Dates.currentMonth()) {
                    Button(v.yillikOdeme == nil ? "Yıllık ödemeyi gir" : "Yıllık ödemeyi değiştir") {
                        tutar = v.yillikOdeme?.tutar ?? v.kalanVergiBorcu
                        tarih = v.yillikOdeme?.tarih ?? Dates.today()
                        duzenlenen = nil
                        yillikDuzenle = true
                    }
                    .font(.footnote.weight(.semibold)).buttonStyle(.plain).foregroundStyle(Palette.accent)
                }
                Text("Her dönemin geçici vergisi, önceki dönemlerde hesaplanan geçici vergiler ve stopaj düşülerek bulunur. "
                     + "Yıllık vergiden yalnız ödemesi girilmiş geçici vergi mahsup edilir; ödenmemiş olan mahsup edilmez.")
                    .font(.caption2).foregroundStyle(Palette.inkFaint)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
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
            if store.state.settings.ek.vergiTuru == "sirket" {
                Toggle("Muhasebeci uygulaması: geçmiş yıl zararını asgari kurumlar vergisi matrahından düş", isOn: Binding(
                    get: { store.state.settings.ek.asgariZararIndirimi == true },
                    set: { yeni in store.ekAyarla { $0.asgariZararIndirimi = yeni ? true : nil } }))
            }
            Picker("%5 vergiye uyum indirimi şartlarını sağlıyor musun?", selection: Binding(
                get: { store.state.settings.ek.uyumIndirimi ?? "" },
                set: { yeni in store.ekAyarla { $0.uyumIndirimi = yeni.isEmpty ? nil : yeni } })) {
                Text("Bilmiyorum").tag("")
                Text("Evet, muhasebecim doğruladı").tag("evet")
                Text("Hayır").tag("hayir")
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
                 + "Tür seçilmezse vergi tahmini yapılmaz. "
                 + "Asgari vergi matrahından geçmiş yıl zararı varsayılan olarak düşülmez: KV Genel Tebliği 23'teki yasak "
                 + "Danıştay 3. Daire'nin E.2024/5700 K.2025/4831 kararıyla iptal edildi, ancak kararın kesinleştiği doğrulanmadı. "
                 + "Muhasebecin düşüyorsa yukarıdan aç. %5 uyum indirimini yalnız muhasebecin şartları doğruladıysa \"Evet\" yap.")
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
