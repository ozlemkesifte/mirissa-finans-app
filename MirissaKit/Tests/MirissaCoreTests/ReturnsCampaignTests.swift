import Testing
import Foundation
@testable import MirissaCore

@Suite("İade analizi ve kampanya hesabı")
struct ReturnsCampaignTests {

    @Test func iadeOraniVeKaybi() {
        var s = Fx.base()
        s.settings.vatEnabled = false
        s.products[0] = Product(id: Fx.sampuanId, name: "Şampuan",
                                costLines: [CostLine(id: "c", label: "Üretim", amount: tl(100))],
                                recipe: [RecipeLine(id: "r", materialId: Fx.koliId, qty: 1, unit: .adet)])
        s.addPurchase("k", "2026-09-01", .material(Fx.koliId), qty: 1_000, paid: tl(10_000))
        s.sales.append(SalesEntry(id: "s", month: "2026-09", channelId: ChannelIds.trendyol,
                                  productId: Fx.sampuanId, qty: 100, grossSales: tl(10_000),
                                  returnsAmount: tl(1_000), returnsQty: 10, returnsRestock: false))
        let l = Engine(s).iadeAnalizi(from: "2026-09", to: "2026-09")
        let r = l.first!
        #expect(r.oranPct == 10)
        #expect(r.iadeTutari == tl(1_000))
        #expect(r.bosaGidenAmbalaj == tl(100))     // 10 iade × 10 TL koli
        #expect(r.hasarliMaliyet == tl(1_000))     // 10 hasarlı × 100 TL
    }

    @Test func kampanyaElleHesaplananlaAyni() {
        var s = Fx.base()
        s.settings.vatEnabled = false
        s.products[1] = Product(id: Fx.serumId, name: "Serum",
                                costLines: [CostLine(id: "c", label: "Üretim", amount: tl(300))])
        s.products[1].setPrice(tl(1_000), channelId: ChannelIds.trendyol, from: "2026-01-01")
        s.channels[0].commissionPct = 10
        s.channels[0].shippingPerOrder = tl(50)
        s.expenses.append(Expense(id: "k", date: "2026-01-01", name: "Kira", amount: tl(11_000),
                                  category: .sabit, recurrence: .aylik))
        let k = Engine(s).kampanyaHesabi(productId: Fx.serumId, channelId: ChannelIds.trendyol,
                                         indirimPct: 20, on: "2026-09-15")!
        #expect(k.yeniFiyat == tl(800))
        #expect(k.eskiKatki == tl(550))    // 1.000 − 100 − 50 − 300
        #expect(k.yeniKatki == tl(370))    // 800 − 80 − 50 − 300
        #expect(abs(k.gerekenSiparisCarpani! - 550.0 / 370) < 1e-9)
        #expect(k.basaBasOnce == 20)       // 11.000 ÷ 550
        #expect(k.basaBasSonra == 30)      // 11.000 ÷ 370 = 29,7 → 30
    }

    @Test func zararliKampanyadaCarpanYok() {
        var s = Fx.base()
        s.settings.vatEnabled = false
        s.products[1] = Product(id: Fx.serumId, name: "Serum",
                                costLines: [CostLine(id: "c", label: "Üretim", amount: tl(700))])
        s.products[1].setPrice(tl(1_000), channelId: ChannelIds.trendyol, from: "2026-01-01")
        s.channels[0].commissionPct = 10
        let k = Engine(s).kampanyaHesabi(productId: Fx.serumId, channelId: ChannelIds.trendyol,
                                         indirimPct: 30, on: "2026-09-15")!
        #expect(k.yeniKatki < 0)
        #expect(k.gerekenSiparisCarpani == nil)
    }
}
