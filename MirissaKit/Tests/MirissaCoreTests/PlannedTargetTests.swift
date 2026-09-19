import Testing
import Foundation
@testable import MirissaCore

/// Hedef, tek bir satış girilmeden de hesaplanabilmeli.
/// Dört senaryo ayrı ayrı doğrulanır.
@Suite("Satış olmadan hedef")
struct PlannedTargetTests {

    private typealias G = Golden.G

    /// Altın senaryo ama hiç satış yok — fiyatlar ve kesintiler tanımlı
    private func satissizDurum() -> AppState {
        var s = Golden.senaryo()
        s.sales = []
        s.channelMonths = []
        // Kanal fiyatları: Trendyol 120, Shopify 110 TL (KDV dahil)
        for id in [G.sampuan, G.serum, G.set, G.ikili] {
            guard let i = s.products.firstIndex(where: { $0.id == id }) else { continue }
            s.products[i].setPrice(tl(1_200), channelId: G.trendyol, from: "2026-01-01")
            s.products[i].setPrice(tl(1_100), channelId: G.shopify, from: "2026-01-01")
        }
        return s
    }

    // MARK: Senaryo 1 — hiç satış yok, tüm maliyetler tanımlı

    @Test func senaryo1_satisYokAmaHedefHesaplanir() {
        var s = satissizDurum()
        // Tek kanal + tek ürün değil: dağılım onayı gerekir
        s.settings.salesMix = SalesMix(
            channelShares: [G.trendyol: 60, G.shopify: 40],
            productShares: [G.sampuan: 100],
            confirmed: true, confirmedAt: "2026-09-01"
        )
        let e = Engine(s)
        let plan = e.plan(month: "2026-09", today: "2026-09-16")

        #expect(plan.mode == .hedef)
        #expect(plan.missing.isEmpty)
        #expect(plan.contributionPerOrder > 0)
        let basaBas = plan.targets.first { $0.isBreakeven }
        #expect((basaBas?.orders ?? 0) > 0)
        #expect((basaBas?.dailyOrders ?? 0) > 0)
        // Kâr hedefleri de üretilir
        // Kullanıcı kâr hedefi girmediği için hazır bir tutar gösterilmez
        #expect(plan.targets.filter { !$0.isBreakeven }.isEmpty)
        #expect(plan.isApproximate)
    }

    /// Sipariş başına katkı elle hesapla uyuşur
    @Test func senaryo1_katkiElleHesaplananlaAyni() {
        var s = satissizDurum()
        s.settings.salesMix = SalesMix(channelShares: [G.trendyol: 100],
                                       productShares: [G.sampuan: 100], confirmed: true)
        let e = Engine(s)
        let u = try? #require(e.unitContribution(productId: G.sampuan,
                                                 channelId: G.trendyol, on: "2026-09-16"))
        // Fiyat 1.200 KDV dahil -> net 1.000
        #expect(u?.price == tl(1_200))
        #expect(u?.netRevenue == tl(1_000))
        // Kesinti: %20 komisyon × 1.200 = 240, + 100 kargo = 340
        #expect(u?.channelFees == tl(340))
        #expect(u?.productCost == tl(100))
        #expect(u?.packagingCost == tl(15))       // kutu 5 + koli 10
        // Katkı: 1.000 − 340 − 100 − 15
        #expect(u?.contribution == tl(545))
        #expect(abs(e.plan(month: "2026-09", today: "2026-09-16").contributionPerOrder
                    - Double(tl(545))) < 1)
    }

    /// Başa baş adedi elle hesapla uyuşur
    @Test func senaryo1_basaBasAdediElleHesaplananlaAyni() {
        var s = satissizDurum()
        s.settings.salesMix = SalesMix(channelShares: [G.trendyol: 100],
                                       productShares: [G.sampuan: 100], confirmed: true)
        let plan = Engine(s).plan(month: "2026-09", today: "2026-09-16")
        // Sabit gider 10.000 TL + bu ay girilmiş 20.000 TL satışa bağlı Trendyol
        // reklamı. Geçmiş satış olmadığı için reklam sipariş başına dağıtılamaz;
        // aylık tutar olarak karşılanması gerekir.
        // (Önceki sürüm reklamı hiç görmüyor ve 19 kargo diyordu — yanlıştı.)
        #expect(plan.fixedCosts == tl(30_000))
        // ceil(30.000 / 545) = 56
        #expect(plan.targets.first { $0.isBreakeven }?.orders == 56)
        // Kullanıcı 25.000 TL kâr hedefi girerse: ceil(55.000 / 545) = 101
        var s2 = s
        s2.settings.profitGoals["2026-09"] = tl(25_000)
        #expect(Engine(s2).plan(month: "2026-09", today: "2026-09-16")
            .targets.first { $0.targetProfit == tl(25_000) }?.orders == 101)
    }

    // MARK: Senaryo 2 — geçmiş satış yok, yaklaşık dağılım tanımlı

    @Test func senaryo2_yaklasikDagilimKullanilir() {
        var s = satissizDurum()
        s.settings.salesMix = SalesMix(
            channelShares: [G.trendyol: 60, G.shopify: 40],
            productShares: [G.sampuan: 40, G.serum: 30, G.set: 20, G.ikili: 10],
            confirmed: true
        )
        let e = Engine(s)
        let (agirliklar, gecmisten, _) = e.targetMix(month: "2026-09")
        #expect(!gecmisten)                       // geçmişten değil, dağılımdan
        #expect(agirliklar.count == 8)            // 2 kanal × 4 SKU
        #expect(abs(agirliklar.reduce(0) { $0 + $1.pay } - 1) < 0.0001)
        // Trendyol + Şampuan payı: %60 × %40
        let pay = agirliklar.first { $0.channelId == G.trendyol && $0.productId == G.sampuan }?.pay
        #expect(abs((pay ?? 0) - 0.24) < 0.0001)

        let plan = e.plan(month: "2026-09", today: "2026-09-16")
        #expect(plan.basis == .beklenenDagilim)
        #expect(plan.isApproximate)
        #expect((plan.targets.first { $0.isBreakeven }?.orders ?? 0) > 0)
    }

    /// Onaylanmamış dağılım kullanılmaz
    @Test func senaryo2_onaylanmamisDagilimKullanilmaz() {
        var s = satissizDurum()
        s.settings.salesMix = SalesMix(channelShares: [G.trendyol: 50, G.shopify: 50],
                                       productShares: [G.sampuan: 100], confirmed: false)
        let plan = Engine(s).plan(month: "2026-09", today: "2026-09-16")
        #expect(plan.targets.isEmpty)
        #expect(plan.missing.contains { $0.kind == .dagilim })
    }

    /// Eşit dağılım yalnızca öneridir
    @Test func esitDagilimOneriOlarakUretilir() {
        let s = satissizDurum()
        let oneri = SalesMix.esitOneri(state: s)
        #expect(oneri.confirmed == false)
        #expect(oneri.channelShares.count == s.activeChannels.count)
        #expect(abs(oneri.channelShares.values.reduce(0, +) - 100) < 0.001)
        #expect(abs(oneri.productShares.values.reduce(0, +) - 100) < 0.001)
    }

    /// Tek kanal + tek ürün varsa sorulacak bir şey yok
    @Test func tekKanalTekUrunDagilimSormaz() {
        var s = satissizDurum()
        s.channels = [s.channels.first { $0.id == G.trendyol }!]
        s.products = s.products.filter { $0.id == G.sampuan }
        let e = Engine(s)
        #expect(e.targetMix(month: "2026-09").agirliklar.count == 1)
        #expect(e.missingForTarget(month: "2026-09", today: "2026-09-16")
            .contains { $0.kind == .dagilim } == false)
        #expect((e.plan(month: "2026-09", today: "2026-09-16")
            .targets.first { $0.isBreakeven }?.orders ?? 0) > 0)
    }

    // MARK: Senaryo 3 — gerçek satış girilmiş ay

    @Test func senaryo3_gercekSatisVarsaGecmisKarisimKullanilir() {
        let e = Engine(Golden.senaryo())
        let (agirliklar, gecmisten, _) = e.targetMix(month: "2026-10")
        #expect(gecmisten)
        #expect(agirliklar.count == 3)            // Eylül'deki 3 satır
        // Eylül'ün gerçek karışımı: 90 + 50 + 20 = 160 net adet
        let sampuanPay = agirliklar.first { $0.productId == G.sampuan }?.pay
        #expect(abs((sampuanPay ?? 0) - 90.0 / 160.0) < 0.0001)

        let plan = e.plan(month: "2026-10", today: "2026-10-01")
        #expect(plan.basis == .gecmisAy("2026-09"))
        #expect(plan.missing.isEmpty)
    }

    /// Ayın kendi satışı girildiyse gerçekleşen gösterilir
    @Test func senaryo3_satisGirilenAyGerceklesenGosterir() {
        let plan = Engine(Golden.senaryo()).plan(month: "2026-09", today: "2026-09-30")
        #expect(plan.mode == .gerceklesen)
        #expect(plan.actual?.revenue == tl(190_000))
        #expect(plan.actual?.profit == tl(75_150))
    }

    // MARK: Senaryo 4 — eksik bilgi

    @Test func senaryo4_eksikBilgiSifirGostermez() {
        var s = satissizDurum()
        s.settings.salesMix = SalesMix(channelShares: [G.trendyol: 100],
                                       productShares: [G.sampuan: 50, G.serum: 50],
                                       confirmed: true)
        // Serum'un Trendyol fiyatı silinsin
        let i = s.products.firstIndex { $0.id == G.serum }!
        s.products[i].priceHistory = nil
        let e = Engine(s)
        let eksikler = e.missingForTarget(month: "2026-09", today: "2026-09-16")
        #expect(eksikler.contains { $0.kind == .fiyat && $0.title.contains("Serum") })
        // Hesap yine de yapılır (fiyatı olanlarla) ama eksik listesi doludur
        #expect(!eksikler.isEmpty)
    }

    @Test func senaryo4_hicFiyatYoksaHedefUretilmez() {
        var s = satissizDurum()
        for i in s.products.indices { s.products[i].priceHistory = nil }
        s.settings.salesMix = SalesMix(channelShares: [G.trendyol: 100],
                                       productShares: [G.sampuan: 100], confirmed: true)
        let e = Engine(s)
        let plan = e.plan(month: "2026-09", today: "2026-09-16")
        #expect(plan.targets.isEmpty)
        #expect(plan.missing.contains { $0.kind == .fiyat })
        // "0 kargo" değil, eksik listesi
        #expect(!plan.missing.isEmpty)
    }

    @Test func senaryo4_sabitGiderYoksaEksikOlarakSoylenir() {
        var s = satissizDurum()
        s.expenses = []
        s.settings.salesMix = SalesMix(channelShares: [G.trendyol: 100],
                                       productShares: [G.sampuan: 100], confirmed: true)
        let eksikler = Engine(s).missingForTarget(month: "2026-09", today: "2026-09-16")
        #expect(eksikler.contains { $0.kind == .sabitGider })
    }

    @Test func senaryo4_bilinmeyenKanalKesintisiEksikSayilir() {
        var s = satissizDurum()
        let i = s.channels.firstIndex { $0.id == G.trendyol }!
        s.channels[i].setRates(ChannelRates(from: "2026-01-01", commissionPct: 20,
                                            unknownFields: ["kargo gideri"]))
        s.settings.salesMix = SalesMix(channelShares: [G.trendyol: 100],
                                       productShares: [G.sampuan: 100], confirmed: true)
        let eksikler = Engine(s).missingForTarget(month: "2026-09", today: "2026-09-16")
        #expect(eksikler.contains { $0.kind == .kanalKesintisi })
    }

    // MARK: Satış başına ne kalıyor

    @Test func satisBasinaKalanKanalaGoreDegisir() {
        var s = satissizDurum()
        s.settings.salesMix = SalesMix(channelShares: [G.trendyol: 50, G.shopify: 50],
                                       productShares: [G.sampuan: 100], confirmed: true)
        let e = Engine(s)
        let liste = e.unitContributions(on: "2026-09-16")
        #expect(liste.count == 8)                 // 2 kanal × 4 SKU
        let t = liste.first { $0.channelId == G.trendyol && $0.productId == G.sampuan }
        let sh = liste.first { $0.channelId == G.shopify && $0.productId == G.sampuan }
        // Shopify: fiyat 1.100 -> net 916,67 ; kesinti %3×1.100 + 60 = 93
        #expect(t?.contribution != sh?.contribution)
        #expect(liste.first?.contribution ?? 0 >= liste.last?.contribution ?? 0)
    }

    @Test func fiyatiOlmayanIkiliListedeGorunmez() {
        var s = satissizDurum()
        let i = s.products.firstIndex { $0.id == G.serum }!
        s.products[i].priceHistory = nil
        let liste = Engine(s).unitContributions(on: "2026-09-16")
        #expect(liste.contains { $0.productId == G.serum } == false)
        #expect(liste.count == 6)
    }

    // MARK: Yıllık

    @Test func yillikHedefSatisOlmadanHesaplanir() {
        var s = satissizDurum()
        s.settings.salesMix = SalesMix(channelShares: [G.trendyol: 100],
                                       productShares: [G.sampuan: 100], confirmed: true)
        let plan = Engine(s).yearlyPlan(year: 2026, today: "2026-09-16")
        let basaBas = plan.targets.first { $0.isBreakeven }
        #expect((basaBas?.ordersPerYear ?? 0) > 0)
        #expect(basaBas?.ordersPerYear == basaBas?.aylik.values.reduce(0, +))
        #expect(basaBas?.ordersPerMonth == basaBas?.aylik.values.max())
        #expect(plan.missing.isEmpty)
    }

    @Test func yillikHedefEksikBilgiyiBildirir() {
        var s = satissizDurum()
        for i in s.products.indices { s.products[i].priceHistory = nil }
        let plan = Engine(s).yearlyPlan(year: 2026, today: "2026-09-16")
        #expect(plan.targets.isEmpty)
        #expect(!plan.missing.isEmpty)
    }
}

/// Ana sayfanın dört senaryosunun ne göstereceği
@Suite("Ana sayfa senaryoları")
struct HomeScenarioTests {

    private typealias G = Golden.G

    private func satissiz() -> AppState {
        var s = Golden.senaryo()
        s.sales = []
        s.channelMonths = []
        for id in [G.sampuan, G.serum, G.set, G.ikili] {
            guard let i = s.products.firstIndex(where: { $0.id == id }) else { continue }
            s.products[i].setPrice(tl(1_200), channelId: G.trendyol, from: "2026-01-01")
            s.products[i].setPrice(tl(1_100), channelId: G.shopify, from: "2026-01-01")
        }
        return s
    }

    /// 1 — Hiç satış yok ama her şey tanımlı: hedef var, gerçekleşen boş
    @Test func senaryo1_hedefVarGerceklesenBos() {
        var s = satissiz()
        s.settings.salesMix = SalesMix(channelShares: [G.trendyol: 60, G.shopify: 40],
                                       productShares: [G.sampuan: 100], confirmed: true)
        let e = Engine(s)
        let plan = e.plan(month: "2026-09", today: "2026-09-16")
        #expect(!plan.targets.isEmpty)               // hedef gösterilir
        #expect(plan.missing.isEmpty)                // eksik yok
        let r = e.companyMonth("2026-09")
        #expect(r.orders == 0)                       // gerçekleşen boş
        #expect(r.gercekCiro == 0)
        // Gider kaydı varsa görünür ama "zarar" iddiası yok
        #expect(r.toplamGider > 0)
    }

    /// 2 — Dağılım sorulmamış: hedef yok, eksik listesinde dağılım var
    @Test func senaryo2_dagilimSorulmamis() {
        let plan = Engine(satissiz()).plan(month: "2026-09", today: "2026-09-16")
        #expect(plan.targets.isEmpty)
        #expect(plan.missing.contains { $0.kind == .dagilim })
        #expect(plan.missing.count >= 1)
    }

    /// 3 — Gerçek satış girilmiş: hem hedef hem gerçekleşen dolu
    @Test func senaryo3_hedefVeGerceklesenBirlikte() {
        let plan = Engine(Golden.senaryo()).plan(month: "2026-09", today: "2026-09-16")
        #expect(plan.mode == .gerceklesen)
        #expect(!plan.targets.isEmpty)
        #expect(plan.actual?.revenue == tl(190_000))
        #expect(plan.targets.first { $0.isBreakeven }?.orders == plan.actual?.breakevenOrders)
        #expect(plan.basis == .ayinKendisi)
    }

    /// 4 — Fiyatlar eksik: sıfır değil, eksik listesi ve tamamlama yolu
    @Test func senaryo4_eksikBilgiListelenir() {
        var s = satissiz()
        s.settings.salesMix = SalesMix(channelShares: [G.trendyol: 100],
                                       productShares: [G.sampuan: 100], confirmed: true)
        for i in s.products.indices { s.products[i].priceHistory = nil }
        let plan = Engine(s).plan(month: "2026-09", today: "2026-09-16")
        #expect(plan.targets.isEmpty)
        #expect(plan.missing.contains { $0.kind == .fiyat })
        // Eksik kalem, hangi ürün ve kanal olduğunu söyler
        let fiyatEksigi = plan.missing.first { $0.kind == .fiyat }
        #expect(fiyatEksigi?.productId != nil)
        #expect(fiyatEksigi?.channelId != nil)
        #expect(fiyatEksigi?.title.contains("fiyatı girilmemiş") == true)
    }
}
