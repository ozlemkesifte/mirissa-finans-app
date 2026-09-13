import Testing
import Foundation
@testable import MirissaCore

@Suite("Reçete, set ve stok düşümü")
struct RecipeTests {

    /// 80 şampuan satıldı -> tüm reçete kalemleri otomatik düşer
    @Test func satisReceteyiOtomatikDuser() {
        var s = Fx.base()
        s.addSale("sal_1", "2026-09", channel: ChannelIds.trendyol, product: Fx.sampuanId,
                  qty: 80, gross: tl(55920))
        let e = Fx.engine(s)
        #expect(e.qty(.product(Fx.sampuanId)) == -80)
        #expect(e.qty(.material(Fx.sampuanKutuId)) == -80)
        #expect(e.qty(.material(Fx.koliId)) == -80)
        #expect(e.qty(.material(Fx.patpatId)) == -80)
        #expect(e.qty(.material(Fx.etiketId)) == -160)   // sipariş başına 2
        #expect(e.qty(.material(Fx.dolguId)) == -1600)   // 80 × 20 gram
    }

    /// 30 set satıldı -> bileşen ürünler ve SETİN kendi reçetesi düşer
    @Test func setSatisiBilesenleriDuser() {
        var s = Fx.base()
        s.addSale("sal_1", "2026-09", channel: ChannelIds.shopify, product: Fx.setId,
                  qty: 30, gross: tl(45000))
        let e = Fx.engine(s)
        #expect(e.qty(.product(Fx.sampuanId)) == -30)
        #expect(e.qty(.product(Fx.serumId)) == -30)
        #expect(e.qty(.material(Fx.setKutuId)) == -30)
        #expect(e.qty(.material(Fx.koliId)) == -30)      // set için 1 koli, bileşen başına değil
        #expect(e.qty(.material(Fx.etiketId)) == -60)
        #expect(e.qty(.material(Fx.dolguId)) == -900)    // 30 × 30 gram
        // Setin kendi kutusu kullanıldığı için şampuan kutusu harcanmaz
        #expect(e.qty(.material(Fx.sampuanKutuId)) == 0)
    }

    /// Set ve tekil ürün aynı malzemeyi paylaşır -> tüketim toplanır
    @Test func ortakMalzemeToplanir() {
        var s = Fx.base()
        s.addSale("sal_1", "2026-09", channel: ChannelIds.trendyol, product: Fx.sampuanId,
                  qty: 80, gross: tl(50000))
        s.addSale("sal_2", "2026-09", channel: ChannelIds.shopify, product: Fx.setId,
                  qty: 30, gross: tl(45000))
        #expect(Fx.engine(s).qty(.material(Fx.koliId)) == -110)
    }

    /// Satış adedi düzeltilince tüketim de düzelir, artık hareket kalmaz
    @Test func satisAdediDuzeltilinceTuketimDuzelir() {
        var s = Fx.base()
        s.addSale("sal_1", "2026-09", channel: ChannelIds.trendyol, product: Fx.sampuanId,
                  qty: 120, gross: tl(60000))
        #expect(Fx.engine(s).qty(.material(Fx.koliId)) == -120)

        s.sales[0].qty = 137
        let e = Fx.engine(s)
        #expect(e.qty(.material(Fx.koliId)) == -137)
        #expect(e.ledger.rows(for: .material(Fx.koliId)).count == 1)  // yetim hareket yok
    }

    /// İade: ürün stoğa döner, ambalaj geri gelmez
    @Test func iadeUrunuGeriGetirirAmbalajiGetirmez() {
        var s = Fx.base()
        s.addSale("sal_1", "2026-09", channel: ChannelIds.trendyol, product: Fx.sampuanId,
                  qty: 100, gross: tl(50000), returnsAmount: tl(2500), returnsQty: 5)
        let e = Fx.engine(s)
        #expect(e.qty(.product(Fx.sampuanId)) == -95)    // 5 tanesi geri geldi
        #expect(e.qty(.material(Fx.koliId)) == -100)     // koli geri gelmez
    }

    /// İade stoğa alınmasın seçilirse ürün de geri gelmez
    @Test func iadeStogaAlinmayabilir() {
        var s = Fx.base()
        s.addSale("sal_1", "2026-09", channel: ChannelIds.trendyol, product: Fx.sampuanId,
                  qty: 100, gross: tl(50000), returnsAmount: tl(2500), returnsQty: 5, restock: false)
        #expect(Fx.engine(s).qty(.product(Fx.sampuanId)) == -100)
    }

    /// Kendini içeren set tanımı çökertmez
    @Test func kendiniIcerenSetCokertmez() {
        var s = Fx.base()
        s.products.append(Product(
            id: "pro_dongu", name: "Döngü", isBundle: true,
            components: [BundleComponent(productId: "pro_dongu", qty: 1)]
        ))
        let e = Fx.engine(s)
        #expect(e.hasCycle("pro_dongu"))
        #expect(e.cost(of: "pro_dongu").total == 0)
    }

    /// Ürün maliyeti: kendi kalemleri + reçete malzemeleri
    @Test func urunMaliyetiDokumu() {
        var s = Fx.base()
        s.products[0] = Fx.sampuan(cost: tl(132))
        s.addPurchase("p1", "2026-01-01", .material(Fx.sampuanKutuId), qty: 100, paid: tl(800))
        s.addPurchase("p2", "2026-01-01", .material(Fx.koliId), qty: 100, paid: tl(1000))
        s.addPurchase("p3", "2026-01-01", .material(Fx.patpatId), qty: 100, paid: tl(200))
        s.addPurchase("p4", "2026-01-01", .material(Fx.etiketId), qty: 200, paid: tl(100))
        s.addPurchase("p5", "2026-01-01", .material(Fx.dolguId), qty: 10, unit: .kg, paid: tl(2000))

        let b = Fx.engine(s).cost(of: Fx.sampuanId)
        #expect(b.ownLines == tl(132))
        // 8 (kutu) + 10 (koli) + 2 (patpat) + 2×0,50 (etiket) + 20×0,20 (dolgu) = 25 TL
        #expect(b.packaging == tl(25))
        #expect(b.total == tl(157))
    }

    /// Set maliyeti = bileşenlerin ÜRETİM maliyeti + setin kendi reçetesi (kutular çift sayılmaz)
    @Test func setMaliyetiCiftSaymaz() {
        var s = Fx.base()
        s.products[0] = Fx.sampuan(cost: tl(132))
        s.products[1] = Fx.serum(cost: tl(139))
        s.addPurchase("p1", "2026-01-01", .material(Fx.setKutuId), qty: 100, paid: tl(1500))
        s.addPurchase("p2", "2026-01-01", .material(Fx.koliId), qty: 100, paid: tl(1000))
        s.addPurchase("p3", "2026-01-01", .material(Fx.patpatId), qty: 100, paid: tl(200))

        let b = Fx.engine(s).cost(of: Fx.setId)
        #expect(b.components == tl(271))                  // 132 + 139
        #expect(b.packaging == tl(15 + 10 + 2))           // set kutusu + koli + patpat
        #expect(b.total == tl(298))
    }

    /// Reçeteden satır silinince maliyet yeniden hesaplanır
    @Test func receteDegisinceMaliyetDuzelir() {
        var s = Fx.base()
        s.addPurchase("p1", "2026-01-01", .material(Fx.koliId), qty: 100, paid: tl(1000))
        let before = Fx.engine(s).cost(of: Fx.sampuanId).packaging
        s.products[0].recipe.removeAll { $0.materialId == Fx.koliId }
        let after = Fx.engine(s).cost(of: Fx.sampuanId).packaging
        #expect(before - after == tl(10))
    }
}
