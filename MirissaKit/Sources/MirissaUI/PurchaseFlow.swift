import SwiftUI
import MirissaCore

/// "Bir şey satın aldım" — adım adım.
struct PurchaseFlow: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    private enum Adim: Hashable, Codable { case kalem, miktar, tutar, kdv, kdvOran, odeme, odemePlani, ozet }

    @State private var adim: Adim = .kalem
    @State private var gecmis: [Adim] = []

    @State private var kalem: ItemRef?
    @State private var miktar: Double = 0
    @State private var birim: UnitCode = .adet
    @State private var tutar: Kurus = 0
    @State private var kdvDahil = true
    @State private var kdvOrani: VatRate = .yirmi
    @State private var kdvSecildi = false
    @State private var oranSecildi = false
    @State private var tarih: DateKey = Dates.today()
    @State private var devamSorusu: WizardDraft?
    @State private var taslakOkundu = false
    @State private var arama = ""
    @State private var vadeli: Bool?
    @State private var pesinat: Kurus = 0
    @State private var taksitSayisi: Double = 1
    @State private var ilkVade: DateKey = Dates.addMonthsToDate(Dates.today(), 1)

    private struct Kayit: Codable {
        var adim: Adim
        var gecmis: [Adim]
        var kalem: ItemRef?
        var miktar: Double
        var birim: UnitCode
        var tutar: Kurus
        var kdvDahil: Bool
        var kdvOrani: VatRate
        var kdvSecildi: Bool
        var oranSecildi: Bool
        var tarih: DateKey
        var vadeli: Bool?
        var pesinat: Kurus?
        var taksitSayisi: Double?
        var ilkVade: DateKey?
    }

    private var taslakKaydi: TaslakKaydi {
        TaslakKaydi(kind: .yeniIslem, subjectId: "alim",
                    baslik: "Stok alımı girişi", toplamAdim: toplamAdim)
    }

    private var kdvAcik: Bool { store.state.settings.vatEnabled }
    private var toplamAdim: Int { kdvAcik ? 7 : 5 }

    private var taslak: StockPurchase? {
        guard let kalem else { return nil }
        var p = StockPurchase(
            date: tarih, item: kalem, qty: miktar, unit: birim, totalPaid: tutar,
            vatRate: kdvAcik ? kdvOrani : nil,
            vatIncluded: kdvAcik ? kdvDahil : nil
        )
        if vadeli == true {
            let brut = p.landedSplit.net + p.landedSplit.vat
            p.odeme = OdemePlani.esit(toplam: brut, pesinat: min(pesinat, brut),
                                      taksitSayisi: Int(taksitSayisi.rounded()), ilkVade: ilkVade)
        }
        return p
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
        case .kalem: kalemAdimi
        case .miktar: miktarAdimi
        case .tutar: tutarAdimi
        case .kdv: kdvAdimi
        case .kdvOran: kdvOranAdimi
        case .odeme: odemeAdimi
        case .odemePlani: odemePlaniAdimi
        case .ozet: ozetAdimi
        }
    }

    private func taslagiGeriYukle() {
        guard let t = taslakKaydi.oku(store, Kayit.self) else { return }
        adim = t.adim; gecmis = t.gecmis; kalem = t.kalem; miktar = t.miktar
        birim = t.birim; tutar = t.tutar; kdvDahil = t.kdvDahil
        kdvOrani = t.kdvOrani; kdvSecildi = t.kdvSecildi
        oranSecildi = t.oranSecildi; tarih = t.tarih
        vadeli = t.vadeli; pesinat = t.pesinat ?? 0; taksitSayisi = t.taksitSayisi ?? 1
        ilkVade = t.ilkVade ?? Dates.addMonthsToDate(Dates.today(), 1)
    }

    private func taslakKaydet() {
        taslakKaydi.kaydet(store, adim: gecmis.count + 1, durum: Kayit(
            adim: adim, gecmis: gecmis, kalem: kalem, miktar: miktar, birim: birim,
            tutar: tutar, kdvDahil: kdvDahil, kdvOrani: kdvOrani,
            kdvSecildi: kdvSecildi, oranSecildi: oranSecildi, tarih: tarih,
            vadeli: vadeli, pesinat: pesinat, taksitSayisi: taksitSayisi, ilkVade: ilkVade))
    }

    // 1
    private var kalemAdimi: some View {
        SoruAdimi(
            soru: "Ne aldın?",
            aciklama: "Satın aldığın ürünü veya malzemeyi seç.",
            adim: 1, toplam: toplamAdim,
            vazgec: { dismiss() }
        ) {
            AramaAlani(placeholder: "Ürün veya malzeme ara", metin: $arama,
                       toplam: store.state.activeProducts.count + store.state.activeMaterials.count)
            VStack(spacing: Metrics.gap) {
                let urunler = araSuz(store.state.activeProducts.filter(\.tracksOwnStock),
                                     arama) { $0.name }
                let malzemeler = araSuz(store.state.activeMaterials, arama) { $0.name }
                if !urunler.isEmpty {
                    baslik("Ürünler")
                    ForEach(urunler) { p in
                        SecenekButonu(baslik: p.name,
                                      aciklama: stokMetni(.product(p.id)),
                                      ikon: "cube.box") {
                            sec(.product(p.id))
                        }
                    }
                }
                if !malzemeler.isEmpty {
                    baslik("Ambalaj ve sarf")
                    ForEach(malzemeler) { m in
                        SecenekButonu(baslik: m.name,
                                      aciklama: stokMetni(.material(m.id)),
                                      ikon: "shippingbox") {
                            sec(.material(m.id))
                        }
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

    // 2
    private var miktarAdimi: some View {
        SoruAdimi(
            soru: "Ne kadar aldın?",
            aciklama: kalem.map { "\(store.state.itemName($0)) — miktarı gir." },
            adim: 2, toplam: toplamAdim,
            ileriAktif: miktar > 0,
            geri: geriGit, vazgec: { dismiss() },
            ileri: { ileri(.tutar) }
        ) {
            BuyukSayiAlani(baslik: "Miktar", birim: birim.displayName, deger: $miktar)
            if let kalem, izinliBirimler.count > 1 {
                Card {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Birim").font(.caption).foregroundStyle(Palette.inkFaint)
                        Picker("", selection: $birim) {
                            ForEach(izinliBirimler) { u in Text(u.displayName).tag(u) }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                    }
                }
                .onAppear { _ = kalem }
            }
        }
    }

    // 3
    private var tutarAdimi: some View {
        SoruAdimi(
            soru: "Toplam ne ödedin?",
            aciklama: "Faturanın tamamı. Kargo ve nakliye dahilse onu da ekle.",
            adim: 3, toplam: toplamAdim,
            ileriAktif: tutar > 0,
            geri: geriGit, vazgec: { dismiss() },
            ileri: { ileri(kdvAcik ? .kdv : .odeme) }
        ) {
            BuyukParaAlani(baslik: "Ödenen toplam", deger: $tutar)
            if miktar > 0, tutar > 0, let kalem {
                birimMaliyetKarti(kalem)
            }
        }
    }

    // 4
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
            ileri(.odeme)
        }
    }

    // Ödeme: peşin mi, vadeli mi
    private var odemeAdimi: some View {
        SoruAdimi(
            soru: "Parasının tamamını şimdi mi ödedin?",
            aciklama: "Fason üretici kalanı teslimde ya da vadeli alıyorsa, ya da kartla taksitli ödediysen "
                + "\"Hayır\" de. Maliyet yine bugün yazılır; yalnızca paranın çıkış zamanı değişir.",
            adim: toplamAdim - 1, toplam: toplamAdim,
            geri: geriGit, vazgec: { dismiss() }
        ) {
            EvetHayirSorusu(evet: "Evet, peşin ödedim", hayir: "Hayır, kalanını sonra ödeyeceğim",
                            secim: vadeli.map { !$0 }) { pesin in
                vadeli = !pesin
                ileri(pesin ? .ozet : .odemePlani)
            }
        }
    }

    private var odemePlaniAdimi: some View {
        let brut = taslak.map { $0.landedSplit.net + $0.landedSplit.vat } ?? tutar
        return SoruAdimi(
            soru: "Nasıl ödeyeceksin?",
            aciklama: "Toplam \(Money.format(brut)). Kalan, eşit taksitlere bölünür.",
            adim: toplamAdim - 1, toplam: toplamAdim,
            ileriAktif: pesinat <= brut && taksitSayisi >= 1,
            geri: geriGit, vazgec: { dismiss() },
            ileri: { ileri(.ozet) }
        ) {
            BuyukParaAlani(baslik: "Bugün ödenen (peşinat, yoksa 0)", deger: $pesinat)
            BuyukSayiAlani(baslik: "Kalan kaç taksitte (vadeli tek ödemeyse 1)", birim: "taksit",
                           deger: $taksitSayisi)
            Card {
                DateRow(label: "İlk ödeme günü", dateKey: $ilkVade)
            }
            if let plan = taslak?.odeme {
                Card(background: Palette.inset) {
                    VStack(spacing: 6) {
                        ForEach(plan.taksitler) { t in
                            LabeledRow(Dates.displayDateShort(t.vade), t.tutar.tl)
                        }
                    }
                }
            }
        }
    }

    // 5
    private var ozetAdimi: some View {
        OzetAdimi(
            ozet: taslak.map { Validation.purchaseSummary($0, state: store.state) }
                ?? SaveSummary(lines: []),
            sorunlar: taslak.map { Validation.purchase($0, state: store.state) } ?? [],
            geri: geriGit,
            vazgec: { dismiss() },
            kaydet: kaydet
        )
    }

    // MARK: Yardımcılar

    private var izinliBirimler: [UnitCode] {
        guard let kalem else { return [.adet] }
        return Units.allowedUnits(baseUnit: store.state.itemBaseUnit(kalem),
                                  packSizes: store.state.itemPackSizes(kalem))
    }

    private func baslik(_ t: String) -> some View {
        Text(t.trUpper)
            .font(.caption.weight(.semibold))
            .tracking(0.6)
            .foregroundStyle(Palette.inkFaint)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func stokMetni(_ ref: ItemRef) -> String {
        "Şu an: " + Units.formatQty(store.engine.qty(ref),
                                    baseUnit: store.state.itemBaseUnit(ref))
    }

    private func birimMaliyetKarti(_ ref: ItemRef) -> some View {
        let taban = store.state.itemBaseUnit(ref)
        let base = Units.toBaseOrNil(qty: miktar, unit: birim, baseUnit: taban,
                                     packSizes: store.state.itemPackSizes(ref)) ?? 0
        let net = kdvAcik ? Vat.net(tutar, rate: kdvOrani, included: kdvDahil) : tutar
        let birimMaliyet = base > 0 ? Money.roundHalfAwayFromZero(Double(net) / base) : 0
        return Card(background: Palette.inset) {
            LabeledRow("1 \(taban.displayName) maliyeti", birimMaliyet.tl,
                       tone: Palette.accent, strong: true)
        }
    }

    private func sec(_ ref: ItemRef) {
        kalem = ref
        birim = store.state.itemBaseUnit(ref)
        ileri(.miktar)
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

    private func kaydet() {
        guard var p = taslak else { return }
        p.id = Ids.make(.purchase)
        store.addPurchase(p)
        taslakKaydi.sil(store)
        dismiss()
    }
}
