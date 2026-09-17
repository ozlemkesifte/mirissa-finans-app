import Testing
import Foundation
@testable import MirissaCore

/// Koli sipariş başına: 1–2 ürünlük sipariş 1 koli, 3 ve üzeri 2 koli.
@Suite("Koli kuralı: sipariş başına")
struct OrderPackagingTests {

    /// Koli 10 TL, patpat 2 TL; ürün başına patpat, sipariş başına koli. KDV yok.
    private func durum(adet: Double, siparis: Int?, buyuk: Int? = nil) -> AppState {
        var s = Fx.base()
        s.settings.vatEnabled = false
        let i = s.materials.firstIndex { $0.id == Fx.koliId }!
        s.materials[i].perOrder = true
        s.addPurchase("k", "2026-09-01", .material(Fx.koliId), qty: 1_000, paid: tl(10_000))
        s.addPurchase("p", "2026-09-01", .material(Fx.patpatId), qty: 1_000, paid: tl(2_000))
        s.products[1] = Fx.serum(cost: tl(100))   // reçete: 1 koli + 1 patpat
        s.addPurchase("u", "2026-09-01", .product(Fx.serumId), qty: 500, paid: tl(50_000))
        s.sales.append(SalesEntry(id: "s", month: "2026-09", channelId: ChannelIds.trendyol,
                                  productId: Fx.serumId, qty: adet, grossSales: tl(adet * 600)))
        if siparis != nil || buyuk != nil {
            s.channelMonths.append(ChannelMonth(id: "cm", month: "2026-09", channelId: ChannelIds.trendyol,
                                                orderCount: siparis, bigOrderCount: buyuk))
        }
        return s
    }

    private func trendyol(_ e: Engine) -> ChannelMonthResult {
        e.companyMonth("2026-09").channels.first { $0.channelId == ChannelIds.trendyol }!
    }

    @Test func ucVeUzeriUrunluSiparisIkiKoli() {
        // 10 sipariş, 22 ürün, 3'ünde 3+ ürün → 13 koli
        let e = Engine(durum(adet: 22, siparis: 10, buyuk: 3))
        #expect(e.qty(.material(Fx.koliId)) == 1_000 - 13)
        #expect(e.qty(.material(Fx.patpatId)) == 1_000 - 22)
        let c = trendyol(e)
        // Ambalaj: 13 koli × 10 + 22 patpat × 2 = 174 TL
        #expect(c.packagingCost == tl(174))
        #expect(c.koliSayisi == 13)
        #expect(!c.koliTahmini)
    }

    @Test func ikiUrunluSiparisTekKoli() {
        let e = Engine(durum(adet: 20, siparis: 10, buyuk: 0))
        #expect(e.qty(.material(Fx.koliId)) == 1_000 - 10)
        #expect(trendyol(e).packagingCost == tl(10 * 10 + 20 * 2))
    }

    @Test func buyukSiparisGirilmemisseEnAzOlabilecekTahminEdilir() {
        // 10 sipariş, 25 ürün: her siparişe 2 ürün = 20, artan 5 ürün → en az 5 siparişte 3+ ürün
        let e = Engine(durum(adet: 25, siparis: 10))
        #expect(e.qty(.material(Fx.koliId)) == 1_000 - 15)
        #expect(trendyol(e).koliTahmini)
        // 18 ürün 10 siparişe sığar → 3+ sipariş olmak zorunda değil
        #expect(Engine(durum(adet: 18, siparis: 10)).qty(.material(Fx.koliId)) == 1_000 - 10)
    }

    @Test func siparisSayisiYoksaHerUrunAyriKoliTahmini() {
        let e = Engine(durum(adet: 20, siparis: nil))
        #expect(e.qty(.material(Fx.koliId)) == 1_000 - 20)
        #expect(trendyol(e).koliTahmini)
    }

    @Test func koliSayisiUrunSayisiniGecmez() {
        // Hatalı giriş: 10 ürün, 30 sipariş → en fazla 10 koli
        let e = Engine(durum(adet: 10, siparis: 30, buyuk: 30))
        #expect(e.qty(.material(Fx.koliId)) == 1_000 - 10)
    }

    @Test func iadeKoliyiGeriGetirmez() {
        var s = durum(adet: 20, siparis: 10, buyuk: 0)
        s.sales[0].returnsQty = 4
        s.sales[0].returnsAmount = tl(2_400)
        #expect(Engine(s).qty(.material(Fx.koliId)) == 1_000 - 10)
    }

    @Test func urunMaliyetiDokumundeKoliAyri() {
        let b = Engine(durum(adet: 1, siparis: nil)).cost(of: Fx.serumId, asOf: "2026-09-30")
        #expect(b.packaging == tl(2))
        #expect(b.orderPackaging == tl(10))
        #expect(b.total == tl(112))
    }

    // MARK: Reklam hedefi

    @Test func reklamHedefiKoliyiSiparisBasinaSayar() {
        var s = durum(adet: 20, siparis: 10, buyuk: 0)
        s.sales[0].month = "2026-08"
        s.channelMonths[0].month = "2026-08"
        s.channels[0].commissionPct = 0
        s.channels[0].shippingPerOrder = tl(50)
        s.products[1].setPrice(tl(600), channelId: ChannelIds.trendyol, from: "2026-01-01")
        let t = Engine(s).adTargets(keepPerOrder: nil, on: "2026-09-10")
            .first { $0.productId == Fx.serumId }!
        // Siparişte 2 ürün, 1 koli: 2 × (600 − 100 − 2) − 50 kargo − 10 koli = 936
        #expect(t.orderValue == tl(1_200))
        #expect(t.beforeAds == tl(936))
    }

    // MARK: Yükleme

    @Test func koliAdliMalzemeSiparisBasinaIsaretlenirSecimeDokunulmaz() throws {
        var s = Fx.base()
        s.materials[0].name = "Kargo Kolisi"
        s.materials[0].perOrder = nil
        s.materials.append(StockMaterial(id: "m2", name: "Büyük koli", perOrder: false))
        let geri = try Persistence.decode(try Persistence.encode(s))
        #expect(geri.material(Fx.koliId)?.perOrder == true)
        #expect(geri.material("m2")?.perOrder == false)
        #expect(geri.material(Fx.patpatId)?.perOrder == nil)
    }
}
