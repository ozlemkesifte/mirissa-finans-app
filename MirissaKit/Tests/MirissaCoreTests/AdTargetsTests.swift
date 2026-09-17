import Testing
import Foundation
@testable import MirissaCore

/// Reklam hedefi: rakamlar elle hesaplanan değerlerle karşılaştırılır.
@Suite("Reklam hedefi (ROAS / CPA)")
struct AdTargetsTests {

    private typealias G = Golden.G

    private func ornek(_ fiyat: Double, _ kalan: Double, birak: Double?) -> AdTarget {
        AdTarget(productId: "p", productName: "Ürün", channelId: "c", channelName: "Site",
                 orderValue: tl(fiyat), beforeAds: tl(kalan),
                 keepPerOrder: birak.map { tl($0) })
    }

    /// 699 TL KDV dahil; reklamdan önce 386,53 TL kalıyor
    @Test func kendiOrnegimizElleHesapla() {
        let t0 = ornek(699, 386.53, birak: nil)
        #expect(abs(t0.breakevenROAS! - 1.8084) < 0.0001)
        // Hedef seçilmemişse en fazla CPA başa baş sınırıdır, hedef ROAS yoktur
        #expect(t0.maxCPA == tl(386.53))
        #expect(t0.targetROAS == nil)

        let t100 = ornek(699, 386.53, birak: 100)
        #expect(t100.maxCPA == tl(286.53))
        #expect(abs(t100.targetROAS! - 2.4395) < 0.0001)

        let t150 = ornek(699, 386.53, birak: 150)
        #expect(t150.maxCPA == tl(236.53))
        #expect(abs(t150.targetROAS! - 2.9552) < 0.0001)

        let t200 = ornek(699, 386.53, birak: 200)
        #expect(t200.maxCPA == tl(186.53))
        #expect(abs(t200.targetROAS! - 3.7474) < 0.0001)
    }

    /// Bırakılmak istenen pay arttıkça hedef ROAS artar, CPA düşer
    @Test func birakilanPayArttikcaHedefZorlasir() {
        var onceki: (roas: Double, cpa: Kurus)? = nil
        for birak in stride(from: 0.0, through: 380, by: 20) {
            let t = ornek(699, 386.53, birak: birak)
            let r = t.targetROAS!
            if let o = onceki {
                #expect(r > o.roas)
                #expect(t.maxCPA < o.cpa)
            }
            // ROAS × CPA her zaman sipariş değerine eşittir
            #expect(abs(r * Double(t.maxCPA) - Double(tl(699))) < 1)
            onceki = (r, t.maxCPA)
        }
    }

    @Test func reklamsizZararVeKaldirmayanHedef() {
        let zarar = ornek(300, -20, birak: nil)
        #expect(zarar.reklamsizZarar)
        #expect(zarar.breakevenROAS == nil)
        #expect(zarar.targetROAS == nil)

        let dar = ornek(699, 120, birak: 150)
        #expect(!dar.reklamsizZarar)
        #expect(dar.hedefiKaldirmiyor)
        #expect(dar.targetROAS == nil)
        #expect(dar.breakevenROAS != nil)
    }

    // MARK: Motor verisiyle

    private func durum() -> AppState {
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

    /// Trendyol Şampuan: fiyat 1.200, reklamdan önce 545 (PlannedTargetTests'te elle doğrulandı)
    @Test func motordanGelenHedefElleUyar() {
        let e = Engine(durum())
        let t = e.adTargets(keepPerOrder: tl(150), on: "2026-09-16")
            .first { $0.productId == G.sampuan && $0.channelId == G.trendyol }
        #expect(t?.orderValue == tl(1_200))
        #expect(t?.beforeAds == tl(545))
        #expect(abs((t?.breakevenROAS ?? 0) - 1_200.0 / 545.0) < 1e-9)
        #expect(t?.maxCPA == tl(395))
        #expect(abs((t?.targetROAS ?? 0) - 1_200.0 / 395.0) < 1e-9)
    }

    /// Karışık hedef: sipariş değeri ve kalan tutar ağırlıklı ortalanır, ROAS sonra bölünür.
    /// (ROAS'ların ortalaması alınmaz — bu yanlış sonuç verir.)
    @Test func karisikHedefAgirlikliHesaplanir() {
        var s = durum()
        s.settings.salesMix = SalesMix(channelShares: [G.trendyol: 60, G.shopify: 40],
                                       productShares: [G.sampuan: 100],
                                       confirmed: true, confirmedAt: "2026-09-01")
        let e = Engine(s)
        let ty = e.unitContribution(productId: G.sampuan, channelId: G.trendyol, on: "2026-09-16")!
        let sh = e.unitContribution(productId: G.sampuan, channelId: G.shopify, on: "2026-09-16")!
        let deger = 0.6 * Double(ty.price) + 0.4 * Double(sh.price)
        let kalan = 0.6 * Double(ty.contribution) + 0.4 * Double(sh.contribution)

        let k = e.blendedAdTarget(month: "2026-09", keepPerOrder: tl(100), today: "2026-09-16")
        #expect(k != nil)
        #expect(k?.orderValue == Money.roundHalfAwayFromZero(deger))
        #expect(k?.beforeAds == Money.roundHalfAwayFromZero(kalan))
        #expect(abs((k?.breakevenROAS ?? 0) - deger / kalan) < 0.001)
        #expect(k?.maxCPA == Money.roundHalfAwayFromZero(kalan) - tl(100))
    }

    @Test func butceHesabi() {
        let e = Engine(durum())
        let t = ornek(699, 386.53, birak: 150)   // CPA 236,53
        // 35.000 TL ÷ 236,53 = 147,97 → en az 148 sipariş gelmeli
        #expect(e.ordersForBudget(tl(35_000), target: t) == 148)
        #expect(e.budgetForOrders(150, target: t) == tl(35_479.50))
        #expect(e.ordersForBudget(tl(1_000), target: ornek(699, 100, birak: 150)) == nil)
    }

    // MARK: Gerçekleşen

    @Test func merVeHukum() {
        let e = Engine(durum())
        let t = ornek(699, 386.53, birak: 150)  // başa baş 1,81 · hedef 2,96
        let bos = AdPerformance(revenue: tl(10_000), adSpend: 0, orders: 10)
        #expect(bos.mer == nil)
        #expect(e.adVerdict(bos, target: t) == .veriYok)
        // Reklam var, satış girilmemiş: "zarar" denmez, veri yok denir
        let satisYok = AdPerformance(revenue: 0, adSpend: tl(10_000), orders: 0)
        #expect(satisYok.mer == nil)
        #expect(e.adVerdict(satisYok, target: t) == .veriYok)

        let kotu = AdPerformance(revenue: tl(15_000), adSpend: tl(10_000), orders: 21)
        #expect(abs(kotu.mer! - 1.5) < 1e-9)
        #expect(kotu.cpa == Money.roundHalfAwayFromZero(Double(tl(10_000)) / 21))
        #expect(e.adVerdict(kotu, target: t) == .zarar)

        let orta = AdPerformance(revenue: tl(25_000), adSpend: tl(10_000), orders: 36)
        #expect(e.adVerdict(orta, target: t) == .basaBasUstu)

        let iyi = AdPerformance(revenue: tl(40_000), adSpend: tl(10_000), orders: 57)
        #expect(e.adVerdict(iyi, target: t) == .hedefUstu)
    }

    /// Gerçekleşen ciro satış kayıtlarının KDV dahil net toplamı, reklam da reklam giderleridir
    @Test func gerceklesenKayitlardanGelir() {
        let s = Golden.senaryo()
        let e = Engine(s)
        let ay = s.sales.map(\.month).max()!
        let p = e.adPerformance(month: ay)
        let beklenenCiro = s.sales.filter { $0.month == ay }.reduce(0) { $0 + $1.netSales }
        #expect(p.revenue == beklenenCiro)
        #expect(p.adSpend == (e.companyMonth(ay).expenseBreakdown[.reklam] ?? 0))
        #expect(p.adSpend > 0)
    }

    /// Ayar kalıcı ve eski dosyalar ayar olmadan açılır
    @Test func ayarKalici() throws {
        var s = AppState.empty
        s.settings.adKeepPerOrder = tl(150)
        let veri = try JSONEncoder().encode(s)
        let geri = try JSONDecoder().decode(AppState.self, from: veri)
        #expect(geri.settings.adKeepPerOrder == tl(150))

        var eski = try JSONSerialization.jsonObject(with: veri) as! [String: Any]
        var ayar = eski["settings"] as! [String: Any]
        ayar.removeValue(forKey: "adKeepPerOrder")
        eski["settings"] = ayar
        let eskiVeri = try JSONSerialization.data(withJSONObject: eski)
        #expect(try JSONDecoder().decode(AppState.self, from: eskiVeri).settings.adKeepPerOrder == nil)
    }
}
