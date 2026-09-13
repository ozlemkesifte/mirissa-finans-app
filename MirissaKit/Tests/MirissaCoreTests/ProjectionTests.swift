import Testing
import Foundation
@testable import MirissaCore

@Suite("Stok uyarıları ve projeksiyon")
struct ProjectionTests {

    private func stoklu() -> AppState {
        var s = Fx.base()
        s.addPurchase("p1", "2026-08-01", .material(Fx.koliId), qty: 500, paid: tl(5000))
        s.addPurchase("p2", "2026-08-01", .material(Fx.etiketId), qty: 1000, paid: tl(500))
        s.addPurchase("p3", "2026-08-01", .material(Fx.dolguId), qty: 20, unit: .kg, paid: tl(4000))
        s.addPurchase("p4", "2026-08-01", .material(Fx.patpatId), qty: 500, paid: tl(1000))
        s.addPurchase("p5", "2026-08-01", .material(Fx.sampuanKutuId), qty: 500, paid: tl(4000))
        return s
    }

    /// Eşik altına inen stoklar uyarı verir, diğerleri ekranı doldurmaz
    @Test func sadeceSorunluStoklarUyarir() {
        var s = stoklu()
        s.materials[0].minQty = 100        // koli
        s.materials[0].criticalQty = 50
        s.addSale("sal_1", "2026-09", channel: ChannelIds.trendyol, product: Fx.sampuanId,
                  qty: 430, gross: tl(200_000))
        let e = Fx.engine(s)
        #expect(e.qty(.material(Fx.koliId)) == 70)
        #expect(e.status(.material(Fx.koliId)) == .azaliyor)

        let alerts = e.stockAlerts(endingAt: "2026-09")
        #expect(alerts.contains { $0.item.id == Fx.koliId })
        #expect(!alerts.contains { $0.item.id == Fx.etiketId })  // etiket bol, uyarmaz
    }

    /// Kritik eşik "sipariş ver" seviyesini ayırır
    @Test func kritikSeviye() {
        var s = stoklu()
        s.materials[0].minQty = 100
        s.materials[0].criticalQty = 50
        s.addSale("sal_1", "2026-09", channel: ChannelIds.trendyol, product: Fx.sampuanId,
                  qty: 458, gross: tl(200_000))
        let e = Fx.engine(s)
        #expect(e.qty(.material(Fx.koliId)) == 42)
        #expect(e.status(.material(Fx.koliId)) == .kritik)
    }

    /// Uyarılar kritik olan en üstte olacak şekilde sıralanır
    @Test func uyarilarKritikOnce() {
        var s = stoklu()
        s.materials[0].minQty = 600        // koli: azalıyor
        s.materials[1].criticalQty = 600   // patpat: kritik
        let alerts = Fx.engine(s).stockAlerts()
        #expect(alerts.first?.status == .kritik)
    }

    /// "Yaklaşık kaç siparişlik kaldı": sipariş başına tüketimden hesaplanır
    @Test func kacSiparislikKaldi() {
        var s = stoklu()
        // 200 sipariş: koli 200, etiket 400, dolgu 4000 g
        s.addSale("sal_1", "2026-09", channel: ChannelIds.trendyol, product: Fx.sampuanId,
                  qty: 200, gross: tl(100_000))
        s.channelMonths.append(ChannelMonth(id: "chm", month: "2026-09",
                                            channelId: ChannelIds.trendyol, orderCount: 200))
        let e = Fx.engine(s)
        #expect(e.qty(.material(Fx.koliId)) == 300)
        #expect(e.ordersLeft(.material(Fx.koliId), endingAt: "2026-09") == 300)   // 1 koli/sipariş

        #expect(e.qty(.material(Fx.etiketId)) == 600)
        #expect(e.ordersLeft(.material(Fx.etiketId), endingAt: "2026-09") == 300) // 2 etiket/sipariş

        #expect(e.qty(.material(Fx.dolguId)) == 16000)
        #expect(e.ordersLeft(.material(Fx.dolguId), endingAt: "2026-09") == 800)  // 20 g/sipariş
    }

    /// Satış verisi yoksa tahmin yapılmaz ("veri yok" gösterilir)
    @Test func veriYoksaTahminYok() {
        let e = Fx.engine(stoklu())
        #expect(e.ordersLeft(.material(Fx.koliId)) == nil)
        #expect(e.monthsLeft(.material(Fx.koliId)) == nil)
    }

    /// Fire ve numune tüketim oranını şişirmez
    @Test func fireTuketimOraniniSismez() {
        var s = stoklu()
        s.addSale("sal_1", "2026-09", channel: ChannelIds.trendyol, product: Fx.sampuanId,
                  qty: 100, gross: tl(50_000))
        s.channelMonths.append(ChannelMonth(id: "chm", month: "2026-09",
                                            channelId: ChannelIds.trendyol, orderCount: 100))
        let withoutFire = Fx.engine(s).consumptionRate(.material(Fx.koliId), endingAt: "2026-09").perOrder

        s.adjustments.append(StockAdjustment(
            id: "adj", date: "2026-09-15", item: .material(Fx.koliId),
            qty: 200, unit: .adet, reason: .hasarli
        ))
        let withFire = Fx.engine(s).consumptionRate(.material(Fx.koliId), endingAt: "2026-09").perOrder
        #expect(withoutFire == withFire)
    }

    /// Hasarlı çıkan malzeme stoktan düşer ve geçmişe yazılır
    @Test func hasarliStoktanDuser() {
        var s = stoklu()
        s.adjustments.append(StockAdjustment(
            id: "adj", date: "2026-09-15", item: .material(Fx.koliId),
            qty: 10, unit: .adet, reason: .hasarli
        ))
        let e = Fx.engine(s)
        #expect(e.qty(.material(Fx.koliId)) == 490)
        let hist = e.history(.material(Fx.koliId))
        #expect(hist.contains { $0.movement.reason == .hasarli && $0.delta == -10 })
    }

    /// Stok değeri = miktar × birim maliyet
    @Test func stokDegeri() {
        let e = Fx.engine(stoklu())
        let b = e.balance(.material(Fx.koliId))
        #expect(b.qty == 500)
        #expect(approx(b.unitCost, Double(tl(10))))
        #expect(b.value == tl(5000))
        #expect(e.totalStockValue == tl(5000 + 500 + 4000 + 1000 + 4000))
    }
}
