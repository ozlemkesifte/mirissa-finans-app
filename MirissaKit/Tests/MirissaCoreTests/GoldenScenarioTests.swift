import Testing
import Foundation
@testable import MirissaCore
import MirissaTestSupport

/// ALTIN SENARYO — bütün rakamlar burada elle hesaplanmıştır.
/// Motor bozulursa ilk bu testler kırılır.
///
/// Kurgu (Eylül 2026):
///   Fiziksel ürünler : Şampuan (net üretim 100 TL), Serum (net üretim 140 TL)
///   Paketler (SKU)   : Set = 1 Şampuan + 1 Serum, 2'li Şampuan = 2 Şampuan
///   Malzemeler       : Şampuan kutusu 5 TL, Koli 10 TL, Set kutusu 15 TL
///   Reçeteler        : Şampuan  -> 1 kutu + 1 koli        (ambalaj 15 TL)
///                      Serum    -> 1 koli                  (ambalaj 10 TL)
///                      Set      -> 1 set kutusu + 1 koli   (ambalaj 25 TL)
///                      2'li     -> 2 kutu + 1 koli         (ambalaj 20 TL)
///   Kanallar         : Trendyol %20 komisyon + 100 TL/sipariş kargo
///                      Shopify  %3 ödeme     +  60 TL/sipariş kargo
///   Başlangıç stoğu  : 500 Şampuan, 300 Serum, 1000 kutu, 1000 koli, 500 set kutusu
@Suite("Altın senaryo — elle hesaplanmış finansal sonuç")
struct GoldenScenarioTests {

    // MARK: Kimlikler

    typealias G = Golden.G

    static func senaryo() -> AppState { Golden.senaryo() }

    private static var e: Engine { Engine(senaryo()) }

    // MARK: 1 — Stok matematiği

    /// Başlangıç + alım + iade − satış tüketimi = mevcut stok
    @Test func stoklarElleHesaplananlaAyni() {
        let e = Self.e
        // Şampuan: 500 − 100 (tekil satış) + 10 (iade) − 50 (set) − 40 (2'li: 2×20)
        #expect(e.qty(.product(G.sampuan)) == 320)
        // Serum: 300 − 50 (set)
        #expect(e.qty(.product(G.serum)) == 250)
        // Setlerin kendi stoğu yoktur
        #expect(e.qty(.product(G.set)) == 0)
        #expect(e.qty(.product(G.ikili)) == 0)
        // Şampuan kutusu: 1000 − 100 (tekil) − 40 (2'li) ; sette kullanılmaz
        #expect(e.qty(.material(G.kutu)) == 860)
        // Koli: 1000 + 500 (alım) − 100 − 50 (set) − 20 (2'li)
        #expect(e.qty(.material(G.koli)) == 1330)
        // Set kutusu: 500 − 50
        #expect(e.qty(.material(G.setKutu)) == 450)
    }

    /// Aynı birim maliyetten alım ortalamayı bozmaz
    @Test func agirlikliOrtalamaKorunur() {
        #expect(Self.e.unitCost(.material(G.koli)) == Double(tl(10)))
    }

    /// Stok değeri: 320×100 + 250×140 + 860×5 + 1330×10 + 450×15
    @Test func stokDegeriDogru() {
        // 32.000 + 35.000 + 4.300 + 13.300 + 6.750 = 91.350
        #expect(Self.e.totalStockValue == tl(91_350))
    }

    // MARK: 2 — Maliyetler

    @Test func urunVeSetMaliyetleriDogru() {
        let e = Self.e
        let ay = Dates.monthEnd("2026-09")
        #expect(e.cost(of: G.sampuan, asOf: ay).intrinsic == tl(100))
        #expect(e.cost(of: G.sampuan, asOf: ay).packaging == tl(15))   // kutu 5 + koli 10
        #expect(e.cost(of: G.serum, asOf: ay).packaging == tl(10))
        // Set: bileşenlerden 100 + 140, kendi maliyet kalemi yok
        #expect(e.cost(of: G.set, asOf: ay).intrinsic == tl(240))
        #expect(e.cost(of: G.set, asOf: ay).ownLines == 0)
        #expect(e.cost(of: G.set, asOf: ay).packaging == tl(25))       // set kutusu 15 + koli 10
        // 2'li: 2 × 100
        #expect(e.cost(of: G.ikili, asOf: ay).intrinsic == tl(200))
        #expect(e.cost(of: G.ikili, asOf: ay).packaging == tl(20))     // 2×5 + 10
    }

    // MARK: 3 — Trendyol kârlılığı

    @Test func trendyolKanalSonucu() {
        let r = Self.e.channelResult(channelId: G.trendyol, month: "2026-09")
        // KDV hariç satışlar: 100.000 + 75.000
        #expect(r.grossSales == tl(175_000))
        #expect(r.returnsAmount == tl(10_000))
        #expect(r.netSales == tl(165_000))
        // Kesintiler KDV DAHİL tutar üzerinden: (120.000−12.000) + 90.000 = 198.000
        #expect(r.netSalesIncVat == tl(198_000))
        #expect(r.units == 150)
        #expect(r.returnedUnits == 10)
        #expect(r.orders == 140)                        // 150 − 10
        #expect(r.commission.amount == tl(39_600))      // 198.000 × %20
        #expect(r.shipping.amount == tl(14_000))        // 140 sipariş × 100 TL
        #expect(r.serviceFee.amount == 0)
        #expect(r.otherDeduction.amount == 0)
        // Ürün maliyeti net adet üzerinden: 90×100 + 50×240
        #expect(r.productCost == tl(21_000))
        // Ambalaj brüt adet üzerinden: 100×15 + 50×25
        #expect(r.packagingCost == tl(2_750))
        // Reklam net 20.000, satışa bağlı
        #expect(r.ads.amount == tl(20_000))
        #expect(r.adsFixed == 0)
        // Toplam gider ve kanalda kalan
        #expect(r.channelFees == tl(53_600))            // 39.600 + 14.000
        #expect(r.totalCost == tl(97_350))              // 53.600 + 20.000 + 21.000 + 2.750
        #expect(r.kanaldaKalan == tl(67_650))           // 165.000 − 97.350
        #expect(r.contribution == tl(67_650))           // sabit kalemi yok
        #expect(r.fixedCost == 0)
    }

    // MARK: 4 — Shopify kârlılığı

    @Test func shopifyKanalSonucu() {
        let r = Self.e.channelResult(channelId: G.shopify, month: "2026-09")
        #expect(r.grossSales == tl(30_000))
        #expect(r.discount == tl(5_000))
        #expect(r.netSales == tl(25_000))
        #expect(r.netSalesIncVat == tl(30_000))
        #expect(r.orders == 20)
        #expect(r.commission.amount == tl(900))         // 30.000 × %3
        #expect(r.shipping.amount == tl(1_200))         // 20 × 60
        #expect(r.productCost == tl(4_000))             // 20 × 200
        #expect(r.packagingCost == tl(400))             // 20 × 20
        #expect(r.totalCost == tl(6_500))
        #expect(r.kanaldaKalan == tl(18_500))
    }

    /// İki kanal birbirinin rakamını etkilemez
    @Test func kanallarBirbirineKarismaz() {
        let e = Self.e
        let t = e.channelResult(channelId: G.trendyol, month: "2026-09")
        let s = e.channelResult(channelId: G.shopify, month: "2026-09")
        #expect(t.ads.amount == tl(20_000))
        #expect(s.ads.amount == 0)                      // reklam yalnız Trendyol'a ait
        #expect(t.commission.amount != s.commission.amount)
    }

    // MARK: 5 — Şirket sonucu

    @Test func sirketSonucuElleHesaplananlaAyni() {
        let r = Self.e.companyMonth("2026-09")
        #expect(r.gercekCiro == tl(190_000))            // 165.000 + 25.000
        #expect(r.ortakGider == tl(10_000))             // muhasebeci net
        #expect(r.toplamKanaldaKalan == tl(86_150))     // 67.650 + 18.500
        #expect(r.gercekKar == tl(76_150))              // 86.150 − 10.000
        #expect(abs(r.karMarjiPct - 40.078947) < 0.001)
        // Toplam gider = kanal giderleri + ortak gider
        #expect(r.toplamGider == tl(113_850))           // 97.350 + 6.500 + 10.000
        // Ciro − gider = kâr
        #expect(r.gercekCiro - r.toplamGider == r.gercekKar)
    }

    /// Kâr ile nakit akışı birbirine karışmaz
    @Test func nakitAkisiKardanAyri() {
        let r = Self.e.companyMonth("2026-09")
        // Nakit: muhasebeci 12.000 + reklam 24.000 + koli alımı 6.000
        //        + kanal kesintileri (53.600 + 2.100)
        #expect(r.nakitCikisi == tl(97_700))
        // Stok alımı kasadan çıktı ama bu ayın gideri değil
        #expect(r.stokAlimi == tl(6_000))
        #expect(r.nakitCikisi != r.gercekKar)
    }

    // MARK: 6 — KDV

    @Test func kdvElleHesaplananlaAyni() {
        let v = Self.e.vatStatus("2026-09")
        // Hesaplanan KDV: net satış KDV dahil 198.000 + 30.000 = 228.000 -> /6
        #expect(v.hesaplanan == tl(38_000))
        // İndirilecek: muhasebeci 2.000 + reklam 4.000 + koli alımı 1.000
        #expect(v.indirilecek == tl(7_000))
        #expect(v.odenecek == tl(31_000))
        #expect(v.devreden == 0)
    }

    /// KDV kârı da nakdi de iki kez etkilemez
    @Test func kdvIkiKezIslenmez() {
        let r = Self.e.companyMonth("2026-09")
        // Kâr KDV hariç tutarlarla: ciro net, giderler net
        #expect(r.gercekCiro == tl(190_000))
        #expect(r.ortakGider == tl(10_000))
        // Nakit KDV dahil
        #expect(r.nakitCikisi == tl(97_700))
    }

    // MARK: 7 — Başa baş ve hedefler

    @Test func aylikBasaBasElleHesaplananlaAyni() {
        let plan = Self.e.plan(month: "2026-10", today: "2026-10-01")
        // Sipariş başına katkı = 86.150 / 160 sipariş = 538,4375 TL
        #expect(abs(plan.contributionPerOrder - 53_843.75) < 0.01)
        // Ekim sabit gideri: muhasebeci aylık -> net 10.000
        #expect(plan.fixedCosts == tl(10_000))
        // Gerekli sipariş = ceil(1.000.000 / 53.843,75) = 19
        let basaBas = plan.targets.first { $0.isBreakeven }
        #expect(basaBas?.orders == 19)
        #expect(basaBas?.dailyOrders == 1)              // ceil(19/31)
        #expect(plan.basis == .gecmisAy("2026-09"))
        #expect(plan.isApproximate)
    }

    @Test func yillikHedefElleHesaplananlaAyni() {
        let plan = Self.e.yearlyPlan(year: 2026, today: "2026-10-01")
        // Muhasebeci Eylül'de başlıyor: Eyl+Eki+Kas+Ara = 4 ay × 10.000 = 40.000
        #expect(plan.fixedCosts == tl(40_000))
        let basaBas = plan.targets.first { $0.isBreakeven }
        // ceil(4.000.000 / 53.843,75) = 75
        #expect(basaBas?.ordersPerYear == 75)
        #expect(basaBas?.ordersPerMonth == 7)           // ceil(75/12)
        #expect(basaBas?.ordersPerDay == 1)             // ceil(75/365)
    }

    /// Yıllık kâr hedefleri de aynı katkıyla hesaplanır
    @Test func yillikKarHedefiElleHesaplananlaAyni() {
        var s = Self.senaryo()
        s.settings.yearlyProfitGoals = ["2026": tl(500_000)]
        let plan = Engine(s).yearlyPlan(year: 2026, today: "2026-10-01")
        let ozel = plan.targets.first { $0.isCustom }
        // ceil((4.000.000 + 50.000.000) / 53.843,75) = ceil(1002,90) = 1003
        #expect(ozel?.ordersPerYear == 1003)
        #expect(ozel?.ordersPerMonth == 84)             // ceil(1004/12)
        #expect(ozel?.ordersPerDay == 3)                // ceil(1004/365)
    }

    // MARK: 8 — Grafik rapor motoruyla aynı

    @Test func grafikRaporlaAyniRakamiGosterir() {
        let e = Self.e
        let nokta = e.trend(endingAt: "2026-09", months: 6).first { $0.month == "2026-09" }
        let rapor = e.companyMonth("2026-09")
        #expect(nokta?.gelir == rapor.gercekCiro)
        #expect(nokta?.gider == rapor.toplamGider)
        #expect(nokta?.kar == rapor.gercekKar)
    }

    /// Eylül grafiğinde Ekim verisi görünmez
    @Test func grafikAylariKaristirmaz() {
        let e = Self.e
        let noktalar = e.trend(endingAt: "2026-09", months: 6)
        #expect(noktalar.count == 6)
        #expect(noktalar.last?.month == "2026-09")
        #expect(noktalar.allSatisfy { $0.month <= "2026-09" })
        // Satış yalnızca Eylül'de: diğer aylar sıfır ciro
        #expect(noktalar.filter { $0.gelir != 0 }.count == 1)
    }

    // MARK: 9 — Yıllık rapor aylık raporların toplamı

    @Test func yillikRaporAylarinToplami() {
        let e = Self.e
        let yil = e.year(2026)
        let aylar = (1...12).map { e.companyMonth(Dates.monthKey(2026, $0)) }
        #expect(yil.gercekCiro == aylar.reduce(0) { $0 + $1.gercekCiro })
        #expect(yil.toplamGider == aylar.reduce(0) { $0 + $1.toplamGider })
        #expect(yil.gercekKar == aylar.reduce(0) { $0 + $1.gercekKar })
    }
}
