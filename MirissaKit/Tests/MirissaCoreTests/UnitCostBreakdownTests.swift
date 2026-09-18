import Testing
import Foundation
@testable import MirissaCore

@Suite("Bir satışın kalem kalem maliyeti")
struct UnitCostBreakdownTests {
    private func durum() -> AppState {
        var s = Fx.base()
        s.settings.vatEnabled = false
        let k = s.materials.firstIndex { $0.id == Fx.koliId }!
        s.materials[k].perOrder = true
        s.addPurchase("k", "2026-09-01", .material(Fx.koliId), qty: 100, paid: tl(1_000))      // 10 TL
        s.addPurchase("p", "2026-09-01", .material(Fx.patpatId), qty: 100, paid: tl(200))      // 2 TL
        s.addPurchase("d", "2026-09-01", .material(Fx.dolguId), qty: 1, unit: .kg, paid: tl(300)) // 0,30 TL/g
        s.products[0] = Product(id: Fx.sampuanId, name: "Şampuan",
                                costLines: [CostLine(id: "c", label: "Üretim", amount: tl(100))],
                                recipe: [RecipeLine(id: "r1", materialId: Fx.koliId, qty: 1, unit: .adet),
                                         RecipeLine(id: "r2", materialId: Fx.patpatId, qty: 1, unit: .adet),
                                         RecipeLine(id: "r3", materialId: Fx.dolguId, qty: 20, unit: .gram)])
        s.products[0].setPrice(tl(1_000), channelId: ChannelIds.trendyol, from: "2026-01-01")
        s.channels[0].commissionPct = 20
        s.channels[0].shippingPerOrder = tl(50)
        return s
    }

    @Test func herKalemAyriVeToplamKatkiylaTutarli() {
        let e = Engine(durum())
        let d = e.birimMaliyetDokumu(productId: Fx.sampuanId, channelId: ChannelIds.trendyol, on: "2026-09-15")!
        func t(_ id: String) -> Kurus? { d.kalemler.first { $0.id == id }?.tutar }
        #expect(t("kalem-c") == tl(100))
        #expect(t("ambalaj-r1") == tl(10))   // koli
        #expect(t("ambalaj-r2") == tl(2))    // patpat
        #expect(t("ambalaj-r3") == tl(6))    // 20 g × 0,30 TL
        #expect(t("kesinti") == tl(200))     // %20 × 1.000
        #expect(t("kargo") == tl(50))
        #expect(d.toplam == tl(368))
        #expect(!d.eksikVar)
        // Satış fiyatı − bu döküm = motorun "siparişte kalan"ı
        let u = e.unitContribution(productId: Fx.sampuanId, channelId: ChannelIds.trendyol, on: "2026-09-15")!
        #expect(u.netRevenue - d.toplam == u.contribution)
    }

    @Test func maliyetiBilinmeyenKalemSifirDiyeGecmez() {
        var s = durum()
        s.purchases.removeAll { $0.id == "p" }       // patpat hiç alınmamış
        s.products[0].costLines = []
        let d = Engine(s).birimMaliyetDokumu(productId: Fx.sampuanId, on: "2026-09-15")!
        #expect(d.eksikVar)
        #expect(d.kalemler.first { $0.id == "ambalaj-r2" }?.bilinmiyor == true)
        #expect(d.kalemler.first { $0.tur == .urun }?.bilinmiyor == true)
    }
}
