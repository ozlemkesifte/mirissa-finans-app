import SwiftUI
import MirissaCore

/// "Eksikleri Tamamla" — hedefi hesaplamak için gereken bilgileri tek tek sorar.
/// Her eksik kalem kendi akışına yönlendirilir; hepsi bitince kapanır.
struct EksikleriTamamlaFlow: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var acilan: AppSheet?
    @State private var fiyatTutar: Kurus = 0
    @State private var duzenlenen: MissingSetupInfo?

    private var eksikler: [MissingSetupInfo] {
        store.engine.missingForTarget(month: Dates.currentMonth())
    }

    var body: some View {
        if let m = duzenlenen, m.kind == .fiyat {
            fiyatAdimi(m)
        } else if eksikler.isEmpty {
            tamamAdimi
        } else {
            listeAdimi
        }
    }

    // MARK: Liste

    private var listeAdimi: some View {
        SoruAdimi(
            soru: "Hedefi hesaplamak için \(eksikler.count) bilgi eksik",
            aciklama: "Birine dokun, sorayım. Hepsini şimdi girmek zorunda değilsin — "
                + "girdiğin her bilgi hedefi daha doğru yapar.",
            vazgec: { dismiss() }
        ) {
            VStack(spacing: Metrics.gap) {
                ForEach(eksikler) { m in
                    SecenekButonu(baslik: m.title,
                                  aciklama: aciklama(m),
                                  ikon: ikon(m),
                                  renk: Palette.uyari) {
                        ac(m)
                    }
                }
            }
        }
    }

    private func ikon(_ m: MissingSetupInfo) -> String {
        switch m.kind {
        case .fiyat: return "tag"
        case .urunMaliyeti: return "cube.box"
        case .kanalKesintisi: return "storefront"
        case .sabitGider: return "repeat"
        case .dagilim: return "chart.pie"
        }
    }

    private func aciklama(_ m: MissingSetupInfo) -> String? {
        switch m.kind {
        case .fiyat: return "Bu kanalda kaça satıyorsun?"
        case .urunMaliyeti: return "Bir adedi sana kaça mal oluyor?"
        case .kanalKesintisi: return "Kanal kurulumunu tamamla"
        case .sabitGider: return "Her ay ödediğin sabit giderleri gir"
        case .dagilim: return "Satışlarının yaklaşık dağılımını sor"
        }
    }

    private func ac(_ m: MissingSetupInfo) {
        switch m.kind {
        case .fiyat:
            fiyatTutar = 0
            duzenlenen = m
        case .urunMaliyeti:
            acilan = m.productId.map { AppSheet.editProduct($0) }
        case .kanalKesintisi:
            acilan = m.channelId.map { AppSheet.channelWizard($0) }
        case .sabitGider:
            acilan = .expenseFlow
        case .dagilim:
            acilan = .satisDagilimi
        }
    }

    // MARK: Fiyat sorusu (en sık eksik olan)

    private func fiyatAdimi(_ m: MissingSetupInfo) -> some View {
        let urun = m.productId.flatMap { store.state.product($0) }
        let kanal = m.channelId.flatMap { store.state.channel($0) }
        return SoruAdimi(
            soru: "\(urun?.name ?? "Ürün") — \(kanal?.name ?? "kanal") fiyatı ne?",
            aciklama: "Müşterinin \(kanal?.name ?? "bu kanalda") gördüğü fiyatı yaz.",
            ileriAktif: fiyatTutar > 0,
            geri: { duzenlenen = nil },
            vazgec: { dismiss() },
            ileri: {
                if let id = m.productId, let kanalId = m.channelId,
                   var p = store.state.product(id) {
                    p.applyCurrentPrice(fiyatTutar, channelId: kanalId, today: Dates.today())
                    store.updateProduct(p)
                }
                fiyatTutar = 0
                duzenlenen = nil
            }
        ) {
            BuyukParaAlani(baslik: "\(urun?.name ?? "") · \(kanal?.name ?? "")",
                           deger: $fiyatTutar)
        }
    }

    // MARK: Bitti

    private var tamamAdimi: some View {
        SoruAdimi(
            soru: "Hedef artık hesaplanabiliyor",
            aciklama: "Ana sayfada bu ay kaç kargo çıkarman gerektiğini görebilirsin.",
            ileriBaslik: "Tamam",
            ileri: { dismiss() }
        ) {
            if let be = store.engine.plan(month: Dates.currentMonth())
                .targets.first(where: { $0.isBreakeven }) {
                Card(background: Palette.karYumusak) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("MASRAFLARI KARŞILAMAK İÇİN")
                            .font(.caption.weight(.semibold))
                            .tracking(0.6)
                            .foregroundStyle(Palette.inkFaint)
                        Text("Yaklaşık \(be.orders) kargo")
                            .font(.system(.title2, design: .rounded).weight(.bold))
                            .foregroundStyle(Palette.ink)
                        Text("Günde ~\(be.dailyOrders) kargo")
                            .font(.subheadline)
                            .foregroundStyle(Palette.uyari)
                    }
                }
            }
        }
        .appSheets($acilan)
    }
}

/// "Satışlarının yaklaşık dağılımı nasıl?" — geçmiş satış yokken hedef için.
/// Eşit dağılım önerilir ama kullanıcı onaylamadan kullanılmaz.
struct SatisDagilimiFlow: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    private enum Adim: Hashable { case kanal, urun, ozet }

    @State private var adim: Adim = .kanal
    @State private var gecmis: [Adim] = []
    @State private var kanalPay: [Id: Double] = [:]
    @State private var urunPay: [Id: Double] = [:]
    @State private var yuklendi = false

    private var kanallar: [Channel] { store.state.activeChannels }
    private var urunler: [Product] { store.state.activeProducts }
    private var kanalToplam: Double { kanalPay.values.reduce(0, +) }
    private var urunToplam: Double { urunPay.values.reduce(0, +) }

    var body: some View {
        icerik.onAppear(perform: yukle)
    }

    @ViewBuilder
    private var icerik: some View {
        switch adim {
        case .kanal: kanalAdimi
        case .urun: urunAdimi
        case .ozet: ozetAdimi
        }
    }

    private func yukle() {
        guard !yuklendi else { return }
        yuklendi = true
        let mevcut = store.state.settings.salesMix ?? SalesMix.esitOneri(state: store.state)
        kanalPay = mevcut.channelShares.filter { k, _ in kanallar.contains { $0.id == k } }
        urunPay = mevcut.productShares.filter { k, _ in urunler.contains { $0.id == k } }
    }

    // MARK: Kanal payları

    private var kanalAdimi: some View {
        SoruAdimi(
            soru: "Satışlarının yaklaşık dağılımı nasıl?",
            aciklama: "Kesin olması gerekmiyor. Hangi kanaldan yüzde kaç satıyorsun?",
            adim: 1, toplam: 2,
            ileriAktif: kanalToplam > 0,
            vazgec: { dismiss() },
            ileri: { ileri(urunler.count > 1 ? .urun : .ozet) }
        ) {
            VStack(spacing: Metrics.gap) {
                ForEach(kanallar) { c in
                    Card {
                        HStack(spacing: 12) {
                            Text(c.name)
                                .font(.headline)
                                .foregroundStyle(Palette.ink)
                            Spacer()
                            PercentField("", value: Binding(
                                get: { kanalPay[c.id] ?? 0 },
                                set: { kanalPay[c.id] = $0 }
                            ))
                            .frame(maxWidth: 110)
                        }
                    }
                }
            }
            toplamNotu(kanalToplam)
            BigButton("Eşit dağıt", icon: "equal", tone: Palette.gider) {
                let pay = kanallar.isEmpty ? 0 : 100.0 / Double(kanallar.count)
                for c in kanallar { kanalPay[c.id] = pay }
            }
        }
    }

    // MARK: Ürün payları

    private var urunAdimi: some View {
        SoruAdimi(
            soru: "Peki hangi üründen ne kadar satıyorsun?",
            aciklama: "Set ve paketler de ayrı birer satış seçeneğidir.",
            adim: 2, toplam: 2,
            ileriAktif: urunToplam > 0,
            geri: geriGit, vazgec: { dismiss() },
            ileri: { ileri(.ozet) }
        ) {
            VStack(spacing: Metrics.gap) {
                ForEach(urunler) { p in
                    Card {
                        HStack(spacing: 12) {
                            Text(p.name)
                                .font(.headline)
                                .foregroundStyle(Palette.ink)
                            Spacer()
                            PercentField("", value: Binding(
                                get: { urunPay[p.id] ?? 0 },
                                set: { urunPay[p.id] = $0 }
                            ))
                            .frame(maxWidth: 110)
                        }
                    }
                }
            }
            toplamNotu(urunToplam)
            BigButton("Eşit dağıt", icon: "equal", tone: Palette.gider) {
                let pay = urunler.isEmpty ? 0 : 100.0 / Double(urunler.count)
                for p in urunler { urunPay[p.id] = pay }
            }
        }
    }

    @ViewBuilder
    private func toplamNotu(_ toplam: Double) -> some View {
        Card(background: abs(toplam - 100) < 0.5 ? Palette.karYumusak : Palette.inset) {
            LabeledRow("Toplam", Money.formatPercent(toplam),
                       tone: abs(toplam - 100) < 0.5 ? Palette.kar : Palette.inkSoft)
        }
        if abs(toplam - 100) >= 0.5, toplam > 0 {
            Text("Toplam %100 olmak zorunda değil; oranlar kendi içinde ölçeklenir.")
                .font(.caption)
                .foregroundStyle(Palette.inkFaint)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: Özet

    private var ozetAdimi: some View {
        OzetAdimi(
            ozet: ozet,
            sorunlar: [],
            kaydetBaslik: "Bu dağılımı kullan",
            geri: geriGit,
            vazgec: { dismiss() },
            kaydet: kaydet
        )
    }

    private var ozet: SaveSummary {
        var satirlar: [String] = []
        let kt = kanalToplam
        for c in kanallar where (kanalPay[c.id] ?? 0) > 0 {
            satirlar.append("\(c.name): \(Money.formatPercent((kanalPay[c.id] ?? 0) / kt * 100))")
        }
        let ut = urunToplam
        for p in urunler where (urunPay[p.id] ?? 0) > 0 {
            satirlar.append("\(p.name): \(Money.formatPercent((urunPay[p.id] ?? 0) / ut * 100))")
        }
        // Onaylanan dağılımla hedefin ne olacağını göster
        var kopya = store.state
        kopya.settings.salesMix = SalesMix(channelShares: kanalPay, productShares: urunPay,
                                           confirmed: true, confirmedAt: Dates.today())
        if let be = Engine(kopya).plan(month: Dates.currentMonth())
            .targets.first(where: { $0.isBreakeven }) {
            satirlar.append("Bu dağılımla masrafları karşılamak için ayda yaklaşık "
                + "\(be.orders) kargo gerekiyor")
        }
        return SaveSummary(
            lines: satirlar,
            note: "Bu yalnızca bir tahmindir; hedefler \"yaklaşık\" olarak gösterilir. "
                + "İlk gerçek ay tamamlanınca sistem senin gerçek satış karışımını kullanır."
        )
    }

    private func kaydet() {
        store.setSalesMix(SalesMix(channelShares: kanalPay, productShares: urunPay,
                                   confirmed: true, confirmedAt: Dates.today()))
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
