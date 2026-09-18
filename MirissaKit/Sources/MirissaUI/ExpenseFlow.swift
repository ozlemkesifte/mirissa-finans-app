import SwiftUI
import MirissaCore

/// "Gider / fatura ödedim" — adım adım.
struct ExpenseFlow: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    private enum Adim: Hashable, Codable { case kategori, ad, tutar, kdv, kdvOran, tekrar, kapsam, ozet }

    @State private var adim: Adim = .kategori
    @State private var gecmis: [Adim] = []

    @State private var secilenKategori: ExpenseCategory?
    @State private var ad = ""
    @State private var tutar: Kurus = 0
    @State private var kdvDahil = true
    @State private var kdvOrani: VatRate = .yirmi
    @State private var kdvSecildi = false
    @State private var oranSecildi = false
    @State private var tekrar: Recurrence = .tek
    @State private var kapsam = "ortak"
    @State private var tarih: DateKey = Dates.today()
    @State private var devamSorusu: WizardDraft?
    @State private var taslakOkundu = false

    private struct Kayit: Codable {
        var adim: Adim
        var gecmis: [Adim]
        var kategori: ExpenseCategory?
        var ad: String
        var tutar: Kurus
        var kdvDahil: Bool
        var kdvOrani: VatRate
        var kdvSecildi: Bool
        var oranSecildi: Bool
        var tekrar: Recurrence
        var kapsam: String
        var tarih: DateKey
    }

    private var taslakKaydi: TaslakKaydi {
        TaslakKaydi(kind: .yeniIslem, subjectId: "gider",
                    baslik: "Gider girişi", toplamAdim: toplamAdim)
    }

    private var kategori: ExpenseCategory { secilenKategori ?? .diger }

    private var kdvAcik: Bool { store.state.settings.vatEnabled }
    private var kanalSorulsun: Bool { store.state.activeChannels.count > 1 }
    private var toplamAdim: Int { 4 + (kdvAcik ? 2 : 0) + (kanalSorulsun ? 1 : 0) }

    private var taslak: Expense {
        Expense(
            date: tarih, name: ad, amount: tutar, category: kategori,
            scope: kapsam == "ortak" ? .ortak : .channel(kapsam),
            recurrence: tekrar,
            vatRate: kdvAcik ? kdvOrani : nil,
            vatIncluded: kdvAcik ? kdvDahil : nil
        )
    }

    var body: some View {
        Group {
            if let d = devamSorusu {
                DevamSorusu(
                    baslik: d.title, ilerleme: d.progressLabel,
                    devam: { taslagiGeriYukle(); devamSorusu = nil },
                    bastan: { taslakKaydi.sil(store); devamSorusu = nil },
                    vazgec: { dismiss() }
                )
            } else {
                icerik
            }
        }
        .onAppear {
            guard !taslakOkundu else { return }
            taslakOkundu = true
            if let d = taslakKaydi.mevcut(store), d.decode(Kayit.self) != nil {
                devamSorusu = d
            }
        }
    }

    @ViewBuilder
    private var icerik: some View {
        switch adim {
        case .kategori: kategoriAdimi
        case .ad: adAdimi
        case .tutar: tutarAdimi
        case .kdv: kdvAdimi
        case .kdvOran: kdvOranAdimi
        case .tekrar: tekrarAdimi
        case .kapsam: kapsamAdimi
        case .ozet: ozetAdimi
        }
    }

    private func taslagiGeriYukle() {
        guard let t = taslakKaydi.oku(store, Kayit.self) else { return }
        adim = t.adim; gecmis = t.gecmis; secilenKategori = t.kategori
        ad = t.ad; tutar = t.tutar; kdvDahil = t.kdvDahil; kdvOrani = t.kdvOrani
        kdvSecildi = t.kdvSecildi; oranSecildi = t.oranSecildi
        tekrar = t.tekrar; kapsam = t.kapsam; tarih = t.tarih
    }

    private func taslakKaydet() {
        taslakKaydi.kaydet(store, adim: gecmis.count + 1, durum: Kayit(
            adim: adim, gecmis: gecmis, kategori: secilenKategori, ad: ad, tutar: tutar,
            kdvDahil: kdvDahil, kdvOrani: kdvOrani,
            kdvSecildi: kdvSecildi, oranSecildi: oranSecildi, tekrar: tekrar,
            kapsam: kapsam, tarih: tarih))
    }

    private var kategoriAdimi: some View {
        SoruAdimi(
            soru: "Ne için ödedin?",
            adim: 1, toplam: toplamAdim,
            vazgec: { dismiss() }
        ) {
            VStack(spacing: Metrics.gap) {
                ForEach(ExpenseCategory.userSelectable) { c in
                    SecenekButonu(baslik: c.displayName,
                                  aciklama: kategoriAciklama(c),
                                  ikon: c.symbolName,
                                  renk: Palette.gider,
                                  secili: secilenKategori == c) {
                        secilenKategori = c
                        ileri(.ad)
                    }
                }
            }
        }
    }

    private func kategoriAciklama(_ c: ExpenseCategory) -> String? {
        switch c {
        case .reklam: return "Meta, Google, pazaryeri reklamı"
        case .kargo: return "Kargo firması faturası"
        case .urunUretimi: return "Fason üretim, hammadde"
        case .influencer: return "İş birliği, PR gönderimi"
        case .sabit: return "Muhasebeci, ajans, abonelik"
        case .ambalaj: return "Koli, kutu, etiket"
        default: return nil
        }
    }

    private var adAdimi: some View {
        AdSorusu(
            soru: "Kime veya ne için?",
            aciklama: "Kısa bir ad yeter: \"Muhasebeci\", \"Meta reklam\", \"ABC Kargo\".",
            placeholder: "Gider adı",
            baslangic: ad,
            adim: 2, toplam: toplamAdim,
            geri: geriGit, vazgec: { dismiss() },
            onDevam: { yeni in
                ad = yeni
                ileri(.tutar)
            }
        )
    }

    private var hazirAdlar: [String] {
        Array(Set(store.state.expenses.filter { $0.category == kategori }.map(\.name)))
            .sorted().prefix(4).map { $0 }
    }

    private var tutarAdimi: some View {
        SoruAdimi(
            soru: "Ne kadar ödedin?",
            adim: 3, toplam: toplamAdim,
            ileriAktif: tutar > 0,
            geri: geriGit, vazgec: { dismiss() },
            ileri: { ileri(kdvAcik && tutar > 0 ? .kdv : .tekrar) }
        ) {
            BuyukParaAlani(baslik: ad.isEmpty ? "Tutar" : ad, deger: $tutar)
        }
    }

    private var kdvAdimi: some View {
        KdvDahilSorusu(
            tutar: tutar, oran: kdvOrani, secim: kdvSecildi ? kdvDahil : nil,
            adim: 4, toplam: toplamAdim,
            geri: geriGit, vazgec: { dismiss() }
        ) { secim in
            kdvDahil = secim
            kdvSecildi = true
            ileri(.kdvOran)
        }
    }

    /// KDV oranı ayrı soru: varsayılan görünür ama seçilmeden geçilmez
    private var kdvOranAdimi: some View {
        KdvOraniSorusu(
            tutar: tutar, dahil: kdvDahil,
            secim: oranSecildi ? kdvOrani : nil,
            adim: 5, toplam: toplamAdim,
            geri: geriGit, vazgec: { dismiss() }
        ) { oran in
            kdvOrani = oran
            oranSecildi = true
            ileri(.tekrar)
        }
    }

    private var tekrarAdimi: some View {
        SoruAdimi(
            soru: "Bu gider her ay tekrar ediyor mu?",
            aciklama: "Her ay ödüyorsan bir kez gir, sonraki aylara kendiliğinden eklensin.",
            adim: kdvAcik ? 5 : 4, toplam: toplamAdim,
            geri: geriGit, vazgec: { dismiss() }
        ) {
            VStack(spacing: Metrics.gap) {
                SecenekButonu(baslik: "Hayır, tek seferlik",
                              ikon: "1.circle", renk: Palette.gider) {
                    tekrar = .tek
                    ileri(kanalSorulsun ? .kapsam : .ozet)
                }
                SecenekButonu(baslik: "Evet, her ay",
                              aciklama: "Muhasebeci, ajans, abonelik gibi",
                              ikon: "repeat") {
                    tekrar = .aylik
                    ileri(kanalSorulsun ? .kapsam : .ozet)
                }
                SecenekButonu(baslik: "Her yıl",
                              aciklama: "Alan adı, yıllık lisans gibi — kâra aylara bölünerek yazılır",
                              ikon: "calendar", renk: Palette.gider) {
                    tekrar = .yillik
                    ileri(kanalSorulsun ? .kapsam : .ozet)
                }
            }
        }
    }

    private var kapsamAdimi: some View {
        SoruAdimi(
            soru: "Bu gider belli bir satış kanalına mı ait?",
            aciklama: "Kanala aitse yalnızca o kanalın kârlılığından düşülür.",
            adim: toplamAdim - 1, toplam: toplamAdim,
            geri: geriGit, vazgec: { dismiss() }
        ) {
            VStack(spacing: Metrics.gap) {
                SecenekButonu(baslik: "Hayır, şirketin geneli",
                              ikon: "building.2", renk: Palette.gider) {
                    kapsam = "ortak"
                    ileri(.ozet)
                }
                ForEach(store.state.activeChannels) { c in
                    SecenekButonu(baslik: "Evet, \(c.name)",
                                  ikon: "storefront") {
                        kapsam = c.id
                        ileri(.ozet)
                    }
                }
            }
        }
    }

    private var ozetAdimi: some View {
        OzetAdimi(
            ozet: Validation.expenseSummary(taslak, state: store.state),
            sorunlar: Validation.expense(taslak, state: store.state),
            geri: geriGit,
            vazgec: { dismiss() },
            kaydet: {
                var e = taslak
                e.id = Ids.make(.expense)
                store.addExpense(e)
                taslakKaydi.sil(store)
                dismiss()
            }
        )
    }

    private func ileri(_ hedef: Adim) {
        gecmis.append(adim)
        withAnimation(.snappy(duration: 0.2)) { adim = hedef }
        taslakKaydet()
    }

    private func geriGit() {
        guard let onceki = gecmis.popLast() else { return }
        withAnimation(.snappy(duration: 0.2)) { adim = onceki }
        taslakKaydet()
    }
}

/// "Stok sayımı yaptım" — adım adım.
struct CountFlow: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    private enum Adim: Hashable, Codable { case kalem, sayim, sebep, ozet }

    @State private var adim: Adim = .kalem
    @State private var gecmis: [Adim] = []
    @State private var kalem: ItemRef?
    @State private var sayilan: Double = 0
    @State private var sebep: AdjustReason = .sayimFarki
    @State private var tarih: DateKey = Dates.today()
    @State private var devamSorusu: WizardDraft?
    @State private var taslakOkundu = false
    @State private var arama = ""

    private struct Kayit: Codable {
        var adim: Adim
        var gecmis: [Adim]
        var kalem: ItemRef?
        var sayilan: Double
        var sebep: AdjustReason
        var tarih: DateKey
    }

    private var taslakKaydi: TaslakKaydi {
        TaslakKaydi(kind: .stokKurulumu, subjectId: nil,
                    baslik: "Stok sayımı", toplamAdim: 3)
    }

    private var sistemdeki: Double { kalem.map { store.engine.qty($0) } ?? 0 }
    private var fark: Double { sayilan - sistemdeki }

    var body: some View {
        Group {
            if let d = devamSorusu {
                DevamSorusu(
                    baslik: d.title, ilerleme: d.progressLabel,
                    devam: { taslagiGeriYukle(); devamSorusu = nil },
                    bastan: { taslakKaydi.sil(store); devamSorusu = nil },
                    vazgec: { dismiss() }
                )
            } else {
                icerik
            }
        }
        .onAppear {
            guard !taslakOkundu else { return }
            taslakOkundu = true
            if let d = taslakKaydi.mevcut(store), d.decode(Kayit.self) != nil {
                devamSorusu = d
            }
        }
    }

    @ViewBuilder
    private var icerik: some View {
        switch adim {
        case .kalem: kalemAdimi
        case .sayim: sayimAdimi
        case .sebep: sebepAdimi
        case .ozet: ozetAdimi
        }
    }

    private func taslagiGeriYukle() {
        guard let t = taslakKaydi.oku(store, Kayit.self) else { return }
        adim = t.adim; gecmis = t.gecmis; kalem = t.kalem
        sayilan = t.sayilan; sebep = t.sebep; tarih = t.tarih
    }

    private func taslakKaydet() {
        taslakKaydi.kaydet(store, adim: gecmis.count + 1, durum: Kayit(
            adim: adim, gecmis: gecmis, kalem: kalem,
            sayilan: sayilan, sebep: sebep, tarih: tarih))
    }

    private var kalemAdimi: some View {
        SoruAdimi(soru: "Neyi saydın?", adim: 1, toplam: 3, vazgec: { dismiss() }) {
            AramaAlani(placeholder: "Ürün veya malzeme ara", metin: $arama,
                       toplam: store.state.activeProducts.count + store.state.activeMaterials.count)
            VStack(spacing: Metrics.gap) {
                let urunler = araSuz(store.state.activeProducts.filter(\.tracksOwnStock),
                                     arama) { $0.name }
                let malzemeler = araSuz(store.state.activeMaterials, arama) { $0.name }
                ForEach(urunler) { p in
                    SecenekButonu(baslik: p.name,
                                  aciklama: "Sistemde: " + Units.formatQty(
                                    store.engine.qty(.product(p.id)), baseUnit: .adet),
                                  ikon: "cube.box") {
                        sec(.product(p.id))
                    }
                }
                ForEach(malzemeler) { m in
                    SecenekButonu(baslik: m.name,
                                  aciklama: "Sistemde: " + Units.formatQty(
                                    store.engine.qty(.material(m.id)), baseUnit: m.baseUnit),
                                  ikon: "shippingbox") {
                        sec(.material(m.id))
                    }
                }
                if urunler.isEmpty && malzemeler.isEmpty {
                    Card(background: Palette.inset) {
                        Text("\"\(arama)\" için sonuç yok.")
                            .font(.footnote)
                            .foregroundStyle(Palette.inkSoft)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }

    private var sayimAdimi: some View {
        let birim = kalem.map { store.state.itemBaseUnit($0) } ?? .adet
        return SoruAdimi(
            soru: "Gerçekte kaç tane var?",
            aciklama: kalem == nil ? nil
                : "Sistemde \(Units.formatQty(sistemdeki, baseUnit: birim)) görünüyor. "
                  + "Depoda saydığın gerçek miktarı yaz.",
            adim: 2, toplam: 3,
            geri: geriGit, vazgec: { dismiss() },
            ileri: { ileri(fark == 0 ? .ozet : .sebep) }
        ) {
            BuyukSayiAlani(baslik: "Saydığın miktar", birim: birim.displayName, deger: $sayilan)
            if fark != 0 {
                Card(background: fark < 0 ? Palette.zararYumusak : Palette.karYumusak) {
                    LabeledRow("FARK",
                               (fark > 0 ? "+" : "") + Units.formatQty(fark, baseUnit: birim),
                               tone: fark < 0 ? Palette.zarar : Palette.kar, strong: true)
                }
            }
        }
    }

    private var sebepAdimi: some View {
        SoruAdimi(
            soru: fark < 0 ? "Eksik çıkanlar neden?" : "Fazla çıkanlar neden?",
            adim: 3, toplam: 3,
            geri: geriGit, vazgec: { dismiss() }
        ) {
            VStack(spacing: Metrics.gap) {
                ForEach([AdjustReason.sayimFarki] + AdjustReason.userSelectable) { r in
                    SecenekButonu(baslik: r.displayName, renk: Palette.gider, secili: sebep == r) {
                        sebep = r
                        ileri(.ozet)
                    }
                }
            }
        }
    }

    private var ozetAdimi: some View {
        let birim = kalem.map { store.state.itemBaseUnit($0) } ?? .adet
        return OzetAdimi(
            ozet: SaveSummary(
                lines: [
                    "\(kalem.map { store.state.itemName($0) } ?? "") stoğu "
                        + "\(Units.formatQty(sayilan, baseUnit: birim)) olarak sabitlenecek",
                    fark == 0 ? "Fark yok" :
                        "Fark: \((fark > 0 ? "+" : "") + Units.formatQty(fark, baseUnit: birim)) "
                        + "(\(sebep.displayName))",
                ],
                note: "Birim maliyet değişmez. Sayım, ait olduğu ayın son sözüdür."
            ),
            sorunlar: [],
            kaydetBaslik: "Sayımı uygula",
            geri: geriGit,
            vazgec: { dismiss() },
            kaydet: {
                guard let kalem else { return }
                store.addCount(StockCount(date: tarih, item: kalem, countedQty: sayilan,
                                          unit: store.state.itemBaseUnit(kalem),
                                          reason: fark == 0 ? nil : sebep))
                taslakKaydi.sil(store)
                dismiss()
            }
        )
    }

    private func sec(_ ref: ItemRef) {
        kalem = ref
        sayilan = store.engine.qty(ref)
        ileri(.sayim)
    }

    private func ileri(_ hedef: Adim) {
        gecmis.append(adim)
        withAnimation(.snappy(duration: 0.2)) { adim = hedef }
        taslakKaydet()
    }

    private func geriGit() {
        guard let onceki = gecmis.popLast() else { return }
        withAnimation(.snappy(duration: 0.2)) { adim = onceki }
        taslakKaydet()
    }
}
