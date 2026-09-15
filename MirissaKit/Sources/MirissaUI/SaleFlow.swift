import SwiftUI
import MirissaCore

/// "Satış gireceğim" — adım adım.
struct SaleFlow: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    private enum Adim: Hashable {
        case ay, kanal, urunSecimi, urunDetay(Int), iadeVarMi, iadeDetay
        case kesintiBiliyorMu, kesintiDetay, ozet
    }

    struct SatirTaslak: Identifiable {
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

    private var toplamAdim: Int { 6 }

    var body: some View {
        switch adim {
        case .ay: ayAdimi
        case .kanal: kanalAdimi
        case .urunSecimi: urunSecimAdimi
        case let .urunDetay(i): urunDetayAdimi(i)
        case .iadeVarMi: iadeSoruAdimi
        case .iadeDetay: iadeDetayAdimi
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
            VStack(spacing: Metrics.gap) {
                ForEach(store.state.activeProducts) { p in
                    SecenekButonu(baslik: p.name,
                                  aciklama: p.isBundle ? "Set" : nil,
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
        }
    }

    // 4 — Her ürün için adet + tutar
    /// Kurulumda girilmiş satış fiyatı — kanala özel varsa o geçerli.
    private func kayitliFiyat(_ i: Int) -> Kurus? {
        guard satirlar.indices.contains(i),
              let p = store.state.product(satirlar[i].urunId) else { return nil }
        return p.price(for: kanalId.isEmpty ? nil : kanalId)
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
                ileri(secim ? .iadeDetay : .kesintiBiliyorMu)
            }
        }
    }

    private var iadeDetayAdimi: some View {
        SoruAdimi(
            soru: "İade ve indirim tutarları",
            adim: 5, toplam: toplamAdim,
            geri: geriGit, vazgec: { dismiss() },
            ileri: { ileri(.kesintiBiliyorMu) }
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

    // 6 — Kanal kesintileri
    private var kesintiSoruAdimi: some View {
        SoruAdimi(
            soru: "Gerçek komisyon ve kargo tutarını biliyor musun?",
            aciklama: "Bilmiyorsan kanal ayarlarındaki oranlardan hesaplarım.",
            adim: 6, toplam: toplamAdim,
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
            adim: 6, toplam: toplamAdim,
            geri: geriGit, vazgec: { dismiss() },
            ileri: { ileri(.ozet) }
        ) {
            BuyukParaAlani(baslik: "Komisyon", deger: $komisyon)
            BuyukParaAlani(baslik: "Kargo", deger: $kargo)
            BuyukSayiAlani(baslik: "Sipariş sayısı (isteğe bağlı)", birim: "sipariş",
                           deger: $siparisSayisi)
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
                vatRate: store.state.settings.vatEnabled ? store.state.settings.defaultVatRate : nil,
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
    }

    private func geriGit() {
        guard let onceki = gecmis.popLast() else { return }
        withAnimation(.snappy(duration: 0.2)) { adim = onceki }
    }

    private func kaydet() {
        for t in taslaklar() { store.addSale(t) }
        if gercekKesinti {
            let mevcut = store.state.channelMonth(month: ay, channelId: kanalId)
            store.upsertChannelMonth(ChannelMonth(
                id: mevcut?.id ?? Ids.make(.channelMonth),
                month: ay, channelId: kanalId,
                orderCount: siparisSayisi > 0 ? Int(siparisSayisi.rounded()) : mevcut?.orderCount,
                commissionActual: komisyon > 0 ? komisyon : nil,
                shippingActual: kargo > 0 ? kargo : nil
            ))
        }
        dismiss()
    }
}

extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}
