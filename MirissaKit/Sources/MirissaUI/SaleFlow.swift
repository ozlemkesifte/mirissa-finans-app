import SwiftUI
import MirissaCore

/// "Satış gireceğim" — adım adım.
struct SaleFlow: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    private enum Adim: Hashable, Codable {
        case ay, kanal, urunSecimi, urunDetay(Int), iadeVarMi, iadeDetay
        case siparis, kesintiBiliyorMu, kesintiDetay, ozet
    }

    struct SatirTaslak: Identifiable, Codable {
        var id: Id
        var urunId: Id
        var ad: String
        var adet: Double = 0
        var tutar: Kurus = 0
    }

    @State private var adim: Adim = .ay
    @State private var gecmis: [Adim] = []

    @State private var ay: MonthKey = Dates.currentMonth()
    @State private var kanalId: Id = ""
    @State private var secilenler: [Id] = []
    @State private var satirlar: [SatirTaslak] = []
    @State private var iadeVar = false
    @State private var indirim: Kurus = 0
    @State private var iadeTutar: Kurus = 0
    @State private var iadeAdet: Double = 0
    @State private var iadeSatilabilir = true
    @State private var gercekKesinti = false
    @State private var komisyon: Kurus = 0
    @State private var kargo: Kurus = 0
    @State private var siparisSayisi: Double = 0
    @State private var buyukSiparis: Double = 0
    @State private var buyukSiparisBiliniyor = false
    @State private var devamSorusu: WizardDraft?
    @State private var taslakOkundu = false
    @State private var urunArama = ""
    @State private var hepsiniGoster = false

    private struct Kayit: Codable {
        var adim: Adim
        var gecmis: [Adim]
        var ay: MonthKey
        var kanalId: Id
        var secilenler: [Id]
        var satirlar: [SatirTaslak]
        var iadeVar: Bool
        var indirim: Kurus
        var iadeTutar: Kurus
        var iadeAdet: Double
        var iadeSatilabilir: Bool
        var gercekKesinti: Bool
        var komisyon: Kurus
        var kargo: Kurus
        var siparisSayisi: Double
        var buyukSiparis: Double?
        var buyukSiparisBiliniyor: Bool?
    }

    private var taslakKaydi: TaslakKaydi {
        TaslakKaydi(kind: .yeniIslem, subjectId: "satis",
                    baslik: "Satış girişi", toplamAdim: toplamAdim)
    }

    private func taslagiGeriYukle() {
        guard let t = taslakKaydi.oku(store, Kayit.self) else { return }
        adim = t.adim; gecmis = t.gecmis; ay = t.ay; kanalId = t.kanalId
        secilenler = t.secilenler; satirlar = t.satirlar; iadeVar = t.iadeVar
        indirim = t.indirim; iadeTutar = t.iadeTutar; iadeAdet = t.iadeAdet
        iadeSatilabilir = t.iadeSatilabilir; gercekKesinti = t.gercekKesinti
        komisyon = t.komisyon; kargo = t.kargo; siparisSayisi = t.siparisSayisi
        buyukSiparis = t.buyukSiparis ?? 0; buyukSiparisBiliniyor = t.buyukSiparisBiliniyor ?? false
    }

    private func taslakKaydet() {
        taslakKaydi.kaydet(store, adim: gecmis.count + 1, durum: Kayit(
            adim: adim, gecmis: gecmis, ay: ay, kanalId: kanalId,
            secilenler: secilenler, satirlar: satirlar, iadeVar: iadeVar,
            indirim: indirim, iadeTutar: iadeTutar, iadeAdet: iadeAdet,
            iadeSatilabilir: iadeSatilabilir, gercekKesinti: gercekKesinti,
            komisyon: komisyon, kargo: kargo, siparisSayisi: siparisSayisi,
            buyukSiparis: buyukSiparis, buyukSiparisBiliniyor: buyukSiparisBiliniyor))
    }

    private var toplamAdim: Int { 7 }

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
        case .ay: ayAdimi
        case .kanal: kanalAdimi
        case .urunSecimi: urunSecimAdimi
        case let .urunDetay(i): urunDetayAdimi(i).id("satisUrun-\(i)")
        case .iadeVarMi: iadeSoruAdimi
        case .iadeDetay: iadeDetayAdimi
        case .siparis: siparisAdimi
        case .kesintiBiliyorMu: kesintiSoruAdimi
        case .kesintiDetay: kesintiDetayAdimi
        case .ozet: ozetAdimi
        }
    }

    // 1 — Ay
    private var ayAdimi: some View {
        SoruAdimi(
            soru: "Hangi ayın satışı?",
            aciklama: "Ay sonunda o ayın toplamını girmen yeterli.",
            adim: 1, toplam: toplamAdim,
            vazgec: { dismiss() }
        ) {
            VStack(spacing: Metrics.gap) {
                ForEach(sonAylar, id: \.self) { m in
                    SecenekButonu(baslik: Dates.displayMonth(m),
                                  aciklama: m == Dates.currentMonth() ? "Bu ay" : nil,
                                  ikon: "calendar",
                                  secili: ay == m) {
                        ay = m
                        ileri(.kanal)
                    }
                }
            }
        }
    }

    private var sonAylar: [MonthKey] {
        let simdi = Dates.currentMonth()
        return (0..<4).map { Dates.addMonths(simdi, -$0) }
    }

    // 2 — Kanal
    private var kanalAdimi: some View {
        SoruAdimi(
            soru: "Hangi kanaldan sattın?",
            adim: 2, toplam: toplamAdim,
            geri: geriGit, vazgec: { dismiss() }
        ) {
            VStack(spacing: Metrics.gap) {
                ForEach(store.state.activeChannels) { c in
                    SecenekButonu(baslik: c.name,
                                  aciklama: kanalAciklama(c),
                                  ikon: "storefront",
                                  secili: kanalId == c.id) {
                        kanalId = c.id
                        ileri(.urunSecimi)
                    }
                }
            }
        }
    }

    private func kanalAciklama(_ c: Channel) -> String? {
        var p: [String] = []
        if c.commissionPct + c.paymentPct > 0 {
            p.append("komisyon \(Money.formatPercent(c.commissionPct + c.paymentPct))")
        }
        if c.shippingPerOrder > 0 { p.append("kargo \(c.shippingPerOrder.tl)") }
        return p.isEmpty ? nil : p.joined(separator: " · ")
    }

    // 3 — Ürün seçimi
    private var urunSecimAdimi: some View {
        SoruAdimi(
            soru: "Hangi ürünlerden sattın?",
            aciklama: "Birden fazla seçebilirsin. Adet ve tutarı sırayla soracağım.",
            adim: 3, toplam: toplamAdim,
            ileriAktif: !secilenler.isEmpty,
            geri: geriGit, vazgec: { dismiss() },
            ileri: satirlariHazirla
        ) {
            AramaAlani(placeholder: "Ürün ara", metin: $urunArama,
                       toplam: store.state.activeProducts.count)
            VStack(spacing: Metrics.gap) {
                ForEach(araSuz(gosterilecekUrunler, urunArama, { $0.name })) { p in
                    SecenekButonu(baslik: p.name,
                                  aciklama: p.isBundle ? "Set / paket" : nil,
                                  ikon: "cube.box",
                                  secili: secilenler.contains(p.id)) {
                        if let i = secilenler.firstIndex(of: p.id) {
                            secilenler.remove(at: i)
                        } else {
                            secilenler.append(p.id)
                        }
                    }
                }
            }
            // Kanalda satıldığı kayıtlı olmayan ürünler varsayılan olarak gizlenir
            if !hepsiniGoster, gizliUrunSayisi > 0 {
                SecenekButonu(baslik: "Listede yok mu? Hepsini göster",
                              aciklama: "\(gizliUrunSayisi) ürün daha var",
                              ikon: "ellipsis.circle", renk: Palette.inkSoft) {
                    withAnimation { hepsiniGoster = true }
                }
            }
        }
    }

    /// Bu kanalda satıldığı kayıtlı olan SKU'lar. Kayıt yoksa hepsi görünür.
    private var gosterilecekUrunler: [Product] {
        let hepsi = store.state.activeProducts
        guard !hepsiniGoster,
              let ch = store.state.channel(kanalId),
              let liste = ch.soldProductIds, !liste.isEmpty else { return hepsi }
        let sinirli = hepsi.filter { liste.contains($0.id) || secilenler.contains($0.id) }
        return sinirli.isEmpty ? hepsi : sinirli
    }

    private var gizliUrunSayisi: Int {
        store.state.activeProducts.count - gosterilecekUrunler.count
    }

    // 4 — Her ürün için adet + tutar
    /// Kurulumda girilmiş satış fiyatı — kanala özel varsa o geçerli.
    private func kayitliFiyat(_ i: Int) -> Kurus? {
        guard satirlar.indices.contains(i),
              let p = store.state.product(satirlar[i].urunId) else { return nil }
        // Satışın ait olduğu ayda geçerli fiyat kullanılır.
        return p.price(for: kanalId.isEmpty ? nil : kanalId, on: Dates.monthEnd(ay))
    }

    private func urunDetayAdimi(_ i: Int) -> some View {
        let satir = satirlar[safe: i]
        return SoruAdimi(
            soru: satir.map { "\($0.ad) — kaç adet, ne kadar?" } ?? "",
            aciklama: satirlar.count > 1 ? "\(i + 1) / \(satirlar.count) ürün" : nil,
            adim: 4, toplam: toplamAdim,
            ileriAktif: (satir?.adet ?? 0) > 0,
            geri: geriGit, vazgec: { dismiss() },
            ileri: {
                if i + 1 < satirlar.count { ileri(.urunDetay(i + 1)) } else { ileri(.iadeVarMi) }
            }
        ) {
            if satirlar.indices.contains(i) {
                BuyukSayiAlani(baslik: "Satılan adet", birim: "adet",
                               deger: Binding(get: { satirlar[i].adet },
                                              set: { adet in
                                                  let onceki = satirlar[i].adet
                                                  satirlar[i].adet = adet
                                                  // Fiyat tanımlıysa tutarı önden doldur;
                                                  // kullanıcı elle değiştirdiyse dokunma.
                                                  guard let fiyat = kayitliFiyat(i) else { return }
                                                  let beklenen = Money.roundHalfAwayFromZero(
                                                    Double(fiyat) * onceki)
                                                  if satirlar[i].tutar == 0 || satirlar[i].tutar == beklenen {
                                                      satirlar[i].tutar = Money.roundHalfAwayFromZero(
                                                        Double(fiyat) * adet)
                                                  }
                                              }))
                BuyukParaAlani(baslik: "Toplam satış tutarı",
                               deger: Binding(get: { satirlar[i].tutar },
                                              set: { satirlar[i].tutar = $0 }))
                if satirlar[i].adet > 0, satirlar[i].tutar > 0 {
                    Card(background: Palette.inset) {
                        LabeledRow("Adet başına",
                                   Money.roundHalfAwayFromZero(
                                    Double(satirlar[i].tutar) / satirlar[i].adet).tl,
                                   tone: Palette.accent)
                    }
                }
            }
        }
    }

    // 5 — İade / indirim
    private var iadeSoruAdimi: some View {
        SoruAdimi(
            soru: "İade veya indirim var mı?",
            aciklama: "Yoksa geç. Varsa tutarları bir sonraki adımda soracağım.",
            adim: 5, toplam: toplamAdim,
            geri: geriGit, vazgec: { dismiss() }
        ) {
            EvetHayirSorusu(
                evet: "Evet, var",
                hayir: "Hayır, yok",
                hayirAciklama: "Doğrudan devam et",
                secim: nil
            ) { secim in
                iadeVar = secim
                ileri(secim ? .iadeDetay : .siparis)
            }
        }
    }

    private var iadeDetayAdimi: some View {
        SoruAdimi(
            soru: "İade ve indirim tutarları",
            adim: 5, toplam: toplamAdim,
            geri: geriGit, vazgec: { dismiss() },
            ileri: { ileri(.siparis) }
        ) {
            BuyukParaAlani(baslik: "İndirim", deger: $indirim)
            BuyukParaAlani(baslik: "İade tutarı", deger: $iadeTutar)
            BuyukSayiAlani(baslik: "İade adedi", birim: "adet", deger: $iadeAdet)
            if iadeAdet > 0 {
                Card {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("İade edilen ürün tekrar satılabilir mi?")
                            .font(.subheadline).foregroundStyle(Palette.ink)
                        Picker("", selection: $iadeSatilabilir) {
                            Text("Evet").tag(true)
                            Text("Hayır, hasarlı").tag(false)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        Text(iadeSatilabilir
                             ? "Stoğa geri eklenir."
                             : "Stoğa geri eklenmez, fire olarak kaydedilir.")
                            .font(.caption2).foregroundStyle(Palette.inkFaint)
                    }
                }
            }
        }
    }

    // 6 — Sipariş ve koli
    private var kanalinAyToplamAdedi: Double {
        let kayitli = store.state.sales.filter { $0.month == ay && $0.channelId == kanalId }
            .reduce(0.0) { $0 + $1.qty }
        return kayitli + satirlar.reduce(0.0) { $0 + $1.adet }
    }

    private var siparisAdimi: some View {
        let mevcut = store.state.channelMonth(month: ay, channelId: kanalId)
        let adet = kanalinAyToplamAdedi
        return SoruAdimi(
            soru: "Bu ay bu kanaldan toplam kaç sipariş (kargo) çıktı?",
            aciklama: "Kargo ve koli sipariş sayısına göre hesaplanır. Bilmiyorsan boş bırak; "
                + "o zaman her ürün ayrı sipariş ve ayrı koli sayılır.",
            adim: 6, toplam: toplamAdim,
            geri: geriGit, vazgec: { dismiss() },
            ileri: { ileri(.kesintiBiliyorMu) }
        ) {
            BuyukSayiAlani(baslik: "Sipariş sayısı (bu ayın toplamı)", birim: "sipariş", deger: $siparisSayisi)
            if siparisSayisi > 0 {
                Card {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Bunlardan kaçında 3 veya daha fazla ürün vardı?")
                            .font(.subheadline.weight(.semibold)).foregroundStyle(Palette.ink)
                        Text("1–2 ürünlük sipariş 1 koli, 3 ve üzeri ürünlü sipariş 2 koli gider.")
                            .font(.caption).foregroundStyle(Palette.inkFaint)
                            .fixedSize(horizontal: false, vertical: true)
                        Picker("", selection: $buyukSiparisBiliniyor) {
                            Text("Biliyorum").tag(true)
                            Text("Bilmiyorum").tag(false)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                    }
                }
                if buyukSiparisBiliniyor {
                    BuyukSayiAlani(baslik: "3+ ürünlü sipariş", birim: "sipariş", deger: $buyukSiparis)
                } else {
                    let tahmin = min(max(Int((adet - 2 * siparisSayisi).rounded(.up)), 0), Int(siparisSayisi))
                    Text("Bu ay toplam \(Int(adet)) ürün \(Int(siparisSayisi)) siparişte gitti. "
                         + (tahmin > 0
                            ? "Her siparişe en fazla 2 ürün sığsaydı \(tahmin) ürün artardı; en az \(tahmin) siparişi 2 koli sayacağım (tahmini)."
                            : "Bu siparişlere 2'şer ürün sığıyor; hepsini 1 koli sayacağım (tahmini)."))
                        .font(.footnote).foregroundStyle(Palette.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .onAppear {
            if siparisSayisi == 0, let o = mevcut?.orderCount { siparisSayisi = Double(o) }
            if buyukSiparis == 0, let b = mevcut?.bigOrderCount {
                buyukSiparis = Double(b)
                buyukSiparisBiliniyor = true
            }
        }
    }

    // 7 — Kanal kesintileri
    private var kesintiSoruAdimi: some View {
        SoruAdimi(
            soru: "Gerçek komisyon ve kargo tutarını biliyor musun?",
            aciklama: "Bilmiyorsan kanal ayarlarındaki oranlardan hesaplarım.",
            adim: 7, toplam: toplamAdim,
            geri: geriGit, vazgec: { dismiss() }
        ) {
            EvetHayirSorusu(
                evet: "Evet, elimde rakamlar var",
                hayir: "Hayır, sen hesapla",
                evetAciklama: "Ekstre veya hakediş raporundan",
                hayirAciklama: kanalOtomatikAciklama,
                secim: nil
            ) { secim in
                gercekKesinti = secim
                ileri(secim ? .kesintiDetay : .ozet)
            }
        }
    }

    private var kanalOtomatikAciklama: String? {
        guard let c = store.state.channel(kanalId) else { return nil }
        return kanalAciklama(c).map { "Ayarlardan: \($0)" }
    }

    private var kesintiDetayAdimi: some View {
        SoruAdimi(
            soru: "Gerçek kesintiler",
            aciklama: "Girdiğin rakamlar otomatik hesabın yerine geçer, üstüne eklenmez.",
            adim: 7, toplam: toplamAdim,
            geri: geriGit, vazgec: { dismiss() },
            ileri: { ileri(.ozet) }
        ) {
            BuyukParaAlani(baslik: "Komisyon", deger: $komisyon)
            BuyukParaAlani(baslik: "Kargo", deger: $kargo)
        }
    }

    // 7 — Özet
    private var ozetAdimi: some View {
        OzetAdimi(
            ozet: toplamOzet,
            sorunlar: tumSorunlar,
            kaydetBaslik: satirlar.count > 1 ? "\(satirlar.count) satışı kaydet" : "Kaydet",
            geri: geriGit,
            vazgec: { dismiss() },
            kaydet: kaydet
        )
    }

    // MARK: Taslaklar

    private func taslaklar() -> [SalesEntry] {
        let toplamTutar = satirlar.reduce(0) { $0 + $1.tutar }
        return satirlar.filter { $0.adet > 0 }.map { satir in
            // İndirim ve iade satırlara tutarlarıyla orantılı dağıtılır
            let pay = toplamTutar > 0 ? Double(satir.tutar) / Double(toplamTutar) : 0
            return SalesEntry(
                id: satir.id,
                month: ay, channelId: kanalId, productId: satir.urunId,
                qty: satir.adet, grossSales: satir.tutar,
                discount: Money.roundHalfAwayFromZero(Double(indirim) * pay),
                returnsAmount: Money.roundHalfAwayFromZero(Double(iadeTutar) * pay),
                returnsQty: satirlar.count == 1 ? iadeAdet : (iadeAdet * pay).rounded(),
                returnsRestock: iadeSatilabilir,
                vatRate: store.state.satisKdvOrani(satir.urunId),
                vatIncluded: store.state.settings.defaultVatIncluded
            )
        }
    }

    private var tumSorunlar: [ValidationIssue] {
        var durum = store.state
        var out: [ValidationIssue] = []
        for t in taslaklar() {
            out += Validation.sale(t, state: durum)
            durum.sales.append(t)
        }
        return out
    }

    private var toplamOzet: SaveSummary {
        var satirMetinleri: [String] = []
        var durum = store.state
        for t in taslaklar() {
            satirMetinleri += Validation.saleSummary(t, state: durum).lines
            durum.sales.append(t)
        }
        if gercekKesinti {
            satirMetinleri.append("Komisyon \(komisyon.tl) ve kargo \(kargo.tl) gerçek tutar olarak kullanılacak")
        }
        return SaveSummary(
            lines: satirMetinleri,
            note: gercekKesinti
                ? "Otomatik kanal hesabı devre dışı kalacak."
                : "Kanal kesintileri ayarlardaki oranlardan hesaplanacak."
        )
    }

    // MARK: Akış

    private func satirlariHazirla() {
        satirlar = secilenler.compactMap { id in
            guard let p = store.state.product(id) else { return nil }
            return SatirTaslak(id: Ids.make(.sale), urunId: id, ad: p.name)
        }
        guard !satirlar.isEmpty else { return }
        ileri(.urunDetay(0))
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
        for t in taslaklar() { store.addSale(t) }
        if gercekKesinti || siparisSayisi > 0 {
            // Var olan elle girilmiş tutarlar korunur; yalnızca bu akışta girilenler güncellenir
            var cm = store.state.channelMonth(month: ay, channelId: kanalId)
                ?? ChannelMonth(month: ay, channelId: kanalId)
            if siparisSayisi > 0 {
                cm.orderCount = Int(siparisSayisi.rounded())
                cm.bigOrderCount = buyukSiparisBiliniyor ? Int(buyukSiparis.rounded()) : nil
            }
            if gercekKesinti {
                cm.commissionActual = komisyon > 0 ? komisyon : nil
                cm.shippingActual = kargo > 0 ? kargo : nil
            }
            store.upsertChannelMonth(cm)
        }
        taslakKaydi.sil(store)
        dismiss()
    }
}

extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}
