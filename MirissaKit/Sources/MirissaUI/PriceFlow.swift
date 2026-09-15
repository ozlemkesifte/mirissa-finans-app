import SwiftUI
import MirissaCore

/// "Fiyatları güncelle" — adım adım. Eski fiyat silinmez,
/// yeni bir geçerlilik kaydı eklenir.
struct PriceUpdateFlow: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    /// Doğrudan bir ürünle açıldığında ilk soru atlanır
    var onUrunId: Id?

    private enum Adim: Hashable { case urun, kanal, fiyat, tarih, ozet }

    @State private var adim: Adim = .urun
    @State private var gecmis: [Adim] = []
    @State private var urunId: Id = ""
    @State private var kanalId: Id?        // nil = etiket fiyatı
    @State private var kanalSecildi = false
    @State private var yeniFiyat: Kurus = 0
    @State private var baslangic: DateKey = Dates.today()
    @State private var tarihSeciliyor = false

    private var urun: Product? { store.state.product(urunId) }
    private var bugun: DateKey { Dates.today() }

    private var eskiFiyat: Kurus? {
        urun?.price(for: kanalId, on: baslangic)
    }

    var body: some View {
        icerik
            .onAppear {
                if let onUrunId, urunId.isEmpty {
                    urunId = onUrunId
                    adim = .kanal
                }
            }
    }

    @ViewBuilder
    private var icerik: some View {
        switch adim {
        case .urun: urunAdimi
        case .kanal: kanalAdimi
        case .fiyat: fiyatAdimi
        case .tarih: tarihAdimi
        case .ozet: ozetAdimi
        }
    }

    // MARK: 1 — Hangi ürün / paket

    private var urunAdimi: some View {
        SoruAdimi(
            soru: "Hangi ürünün fiyatı değişti?",
            adim: 1, toplam: 4,
            vazgec: { dismiss() }
        ) {
            VStack(spacing: Metrics.gap) {
                ForEach(store.state.activeProducts) { p in
                    SecenekButonu(baslik: p.name,
                                  aciklama: fiyatOzeti(p),
                                  ikon: p.isBundle ? "shippingbox.and.arrow.backward" : "cube.box",
                                  secili: urunId == p.id) {
                        urunId = p.id
                        ileri(.kanal)
                    }
                }
            }
        }
    }

    private func fiyatOzeti(_ p: Product) -> String? {
        let bugunku = p.price(on: bugun)
        guard let bugunku else { return "Fiyat girilmemiş" }
        var parcalar = ["Etiket: \(Money.format(bugunku))"]
        for c in store.state.activeChannels {
            if let f = p.price(for: c.id, on: bugun), f != bugunku {
                parcalar.append("\(c.name): \(Money.format(f))")
            }
        }
        return parcalar.joined(separator: " · ")
    }

    // MARK: 2 — Hangi kanal

    private var kanalAdimi: some View {
        SoruAdimi(
            soru: "Hangi kanalda?",
            aciklama: "Bütün kanallarda aynı fiyatla satıyorsan etiket fiyatını seç.",
            adim: 2, toplam: 4,
            geri: geriGit, vazgec: { dismiss() }
        ) {
            VStack(spacing: Metrics.gap) {
                SecenekButonu(baslik: "Etiket fiyatı (hepsi)",
                              aciklama: kanalFiyatAciklama(nil),
                              ikon: "tag", secili: kanalSecildi && kanalId == nil) {
                    kanalId = nil
                    kanalSecildi = true
                    hazirla()
                    ileri(.fiyat)
                }
                ForEach(store.state.activeChannels) { c in
                    SecenekButonu(baslik: c.name,
                                  aciklama: kanalFiyatAciklama(c.id),
                                  ikon: "storefront", secili: kanalId == c.id) {
                        kanalId = c.id
                        kanalSecildi = true
                        hazirla()
                        ileri(.fiyat)
                    }
                }
            }
        }
    }

    private func kanalFiyatAciklama(_ id: Id?) -> String? {
        guard let p = urun, let f = p.price(for: id, on: bugun) else { return "Fiyat girilmemiş" }
        return "Şu anki fiyat: \(Money.format(f))"
    }

    private func hazirla() {
        if yeniFiyat == 0, let f = urun?.price(for: kanalId, on: bugun) { yeniFiyat = f }
    }

    // MARK: 3 — Yeni fiyat

    private var fiyatAdimi: some View {
        SoruAdimi(
            soru: "Yeni fiyat ne?",
            aciklama: eskiFiyat.map { "Şu anki fiyat \(Money.format($0))." },
            adim: 3, toplam: 4,
            ileriAktif: yeniFiyat > 0,
            geri: geriGit, vazgec: { dismiss() },
            ileri: { ileri(.tarih) }
        ) {
            BuyukParaAlani(baslik: baslik, deger: $yeniFiyat)
            if let eski = eskiFiyat, eski > 0, yeniFiyat > 0, yeniFiyat != eski {
                let fark = yeniFiyat - eski
                Card(background: fark > 0 ? Palette.karYumusak : Palette.zararYumusak) {
                    LabeledRow(fark > 0 ? "ZAM" : "İNDİRİM",
                               (fark > 0 ? "+" : "") + Money.format(fark)
                                + "  (\(Money.formatPercent(Double(fark) / Double(eski) * 100)))",
                               tone: fark > 0 ? Palette.kar : Palette.zarar, strong: true)
                }
            }
        }
    }

    private var baslik: String {
        let kanalAd = kanalId.flatMap { store.state.channel($0)?.name } ?? "Etiket"
        return "\(urun?.name ?? "Ürün") — \(kanalAd)"
    }

    // MARK: 4 — Ne zamandan itibaren

    private var tarihAdimi: some View {
        SoruAdimi(
            soru: "Ne zamandan itibaren geçerli?",
            aciklama: "Eski fiyat silinmez. O tarihe kadarki satışlar ve raporlar "
                + "eski fiyatla kalır.",
            adim: 4, toplam: 4,
            ileriAktif: true,
            geri: geriGit, vazgec: { dismiss() },
            ileri: tarihSeciliyor ? { ileri(.ozet) } : nil
        ) {
            VStack(spacing: Metrics.gap) {
                SecenekButonu(baslik: "Bugünden itibaren",
                              aciklama: Dates.displayDate(bugun),
                              ikon: "calendar.badge.clock") {
                    baslangic = bugun
                    tarihSeciliyor = false
                    ileri(.ozet)
                }
                SecenekButonu(baslik: "Tarih seç",
                              aciklama: "Geçmiş ya da ileri bir tarih",
                              ikon: "calendar", secili: tarihSeciliyor) {
                    withAnimation { tarihSeciliyor = true }
                }
            }
            if tarihSeciliyor {
                Card {
                    DateRow(label: "Geçerlilik başlangıcı", dateKey: $baslangic)
                }
                if Dates.daysBetween(bugun, baslangic) > 0 {
                    Card(background: Palette.inset) {
                        Text("Bu fiyat \(Dates.displayDate(baslangic)) tarihinde "
                             + "kendiliğinden geçerli olacak.")
                            .font(.footnote)
                            .foregroundStyle(Palette.inkSoft)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }

    // MARK: Özet

    private var ozetAdimi: some View {
        OzetAdimi(
            ozet: ozet,
            sorunlar: sorunlar,
            kaydetBaslik: "Fiyatı kaydet",
            geri: geriGit,
            vazgec: { dismiss() },
            kaydet: kaydet
        )
    }

    private var sorunlar: [ValidationIssue] {
        guard yeniFiyat > 0 else {
            return [ValidationIssue(.gecersizTutar, .engel, "Fiyat girilmedi",
                                    "Sıfırdan büyük bir fiyat yaz.")]
        }
        return []
    }

    private var ozet: SaveSummary {
        var satirlar: [String] = []
        let kanalAd = kanalId.flatMap { store.state.channel($0)?.name } ?? "tüm kanallar"
        satirlar.append("\(urun?.name ?? "Ürün") — \(kanalAd): "
            + "\(Money.format(yeniFiyat)), \(Dates.displayDate(baslangic)) tarihinden itibaren")
        if let eski = eskiFiyat, eski > 0 {
            satirlar.append("\(Money.format(eski)) olan eski fiyat silinmez; "
                + "o tarihe kadarki raporlar aynı kalır")
        }
        if let (once, sonra) = hedefOnizleme() {
            satirlar.append("Bu değişiklikten sonra yaklaşık başa baş hedefin "
                + "\(once) siparişten \(sonra) siparişe değişecek")
        }
        return SaveSummary(lines: satirlar)
    }

    /// "Başa baş hedefin X siparişten Y siparişe değişecek" önizlemesi.
    /// Hesap motoru değişmez: yeni fiyatla geçici bir durum kurulup
    /// aynı hesap yeniden çalıştırılır.
    private func hedefOnizleme() -> (Int, Int)? {
        let ay = Dates.month(of: max(baslangic, bugun))
        let once = store.engine.plan(month: ay, today: bugun)
        guard let oncekiHedef = once.targets.first(where: { $0.isBreakeven })?.orders,
              var p = urun else { return nil }
        p.setPrice(yeniFiyat, channelId: kanalId, from: baslangic)
        var kopya = store.state
        guard let i = kopya.products.firstIndex(where: { $0.id == p.id }) else { return nil }
        kopya.products[i] = p
        let sonra = Engine(kopya).plan(month: ay, today: bugun)
        guard let yeniHedef = sonra.targets.first(where: { $0.isBreakeven })?.orders,
              yeniHedef != oncekiHedef else { return nil }
        return (oncekiHedef, yeniHedef)
    }

    private func kaydet() {
        guard var p = urun else { return }
        p.setPrice(yeniFiyat, channelId: kanalId, from: baslangic)
        store.updateProduct(p)
        store.markPriceCheck()
        dismiss()
    }

    private func ileri(_ hedef: Adim) {
        gecmis.append(adim)
        withAnimation(.snappy(duration: 0.2)) { adim = hedef }
    }

    private func geriGit() {
        guard let onceki = gecmis.popLast() else { return }
        withAnimation(.snappy(duration: 0.2)) { adim = onceki }
    }
}

// MARK: - Ana sayfadaki hatırlatma kartı

/// Süresi gelince çıkar: mevcut fiyatları kısaca gösterir,
/// iki seçenek sunar. Menü eklemez, yer kaplamaz.
struct PriceCheckCard: View {
    @Environment(AppStore.self) private var store
    @Binding var sheet: AppSheet?

    private var bugun: DateKey { Dates.today() }

    private var gosterilsin: Bool {
        store.state.settings.priceCheckDue(on: bugun)
            && !store.state.activeProducts.isEmpty
    }

    var body: some View {
        if gosterilsin {
            Card {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 10) {
                        Image(systemName: "tag.circle.fill")
                            .font(.title3)
                            .foregroundStyle(Palette.accent)
                        Text("Fiyat kontrolü zamanı")
                            .font(.headline)
                            .foregroundStyle(Palette.ink)
                    }
                    VStack(spacing: 8) {
                        ForEach(store.state.activeProducts.prefix(4)) { p in
                            LabeledRow(p.name, fiyatMetni(p))
                        }
                    }
                    HStack(spacing: Metrics.gap) {
                        Button("Değişiklik yok") { store.markPriceCheck() }
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Palette.inkSoft)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Palette.inset)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        Button("Fiyatları güncelle") { sheet = .priceUpdate(nil) }
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Palette.onFilled)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Palette.accent)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    /// Kanala göre değişiyorsa aralık gösterilir: "650 – 699 TL"
    private func fiyatMetni(_ p: Product) -> String {
        guard let etiket = p.price(on: bugun) else { return "Fiyat yok" }
        var hepsi = [etiket]
        for c in store.state.activeChannels {
            if let f = p.price(for: c.id, on: bugun) { hepsi.append(f) }
        }
        let enAz = hepsi.min() ?? etiket
        let enCok = hepsi.max() ?? etiket
        return enAz == enCok
            ? Money.format(enCok)
            : "\(Money.format(enAz)) – \(Money.format(enCok))"
    }
}
